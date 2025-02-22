/* ========================================================================== */
/* CONFIGURATION OPTIONS / ENVIRONMENT VARIABLES                              */
/* ========================================================================== */

locals {

  # Parse container definition and exclude fields that are better defined as
  # environment variables (see below).

  container = {
    for k, v in var.container : k => v if !contains(["image", "container_name", "command"], k)
  }

  # image can be either var.container.image (as is documented) or
  # var.image (as previously implemented)
  image = lookup(var.container, "image", var.image)

  # Define environment variables that will be written to `/var/app/.env` and
  # made available to all running services, including Docker Compose and systemd.

  # The list below is not exhaustive, refer to the Docker documentation for additional
  # configuration options (https://docs.docker.com/compose/reference/envvars/)

  environment = merge({
    DOMAIN                     = var.domain
    COMPOSE_DOCKER_IMAGE       = "docker/compose"
    COMPOSE_DOCKER_TAG         = "1.29.2"
    IMAGE_NAME                 = local.image
    CONTAINER_NAME             = lookup(var.container, "container_name", null)
    CONTAINER_COMMAND          = lookup(var.container, "command", null)
    CONTAINER_PORT             = var.port
    DOCKER_NETWORK             = "web"
    DOCKER_LOG_DRIVER          = null
    CADDY_ENABLED              = null
    CADDY_IMAGE_TAG            = null
    CADDY_LOG_LEVEL            = null
    CADDY_OPS_PORT             = null
    CADDY_ADMIN_PORT           = null
    WEBHOOK_URL_PREFIX         = var.enable_webhook ? "hooks" : null
    WEBHOOK_HTTP_METHOD        = var.enable_webhook ? "PATCH" : null
  }, var.env)

  login = var.registry_user != null ? "-u ${var.registry_user} -p ${var.registry_password} ${var.registry_url}" : null
}

/* ========================================================================== */
/* DOCKER COMPOSE FILE(S)                                                     */
/* ========================================================================== */

locals {
  template_dir = "${path.module}/templates"
  file_regex   = "(?P<filename>docker-compose(?:\\.(?P<name>.*?))?\\.ya?ml)"

  # Merge the container definition provided by the user with the default template.
  # The resulting object should match the schema expected by Docker Compose.

  docker_compose_template_yaml = file("${local.template_dir}/docker-compose.default.yaml")
  docker_compose_template      = yamldecode(local.docker_compose_template_yaml)

  docker_compose = {
    version = "3.3"
    services = {
      app = merge(local.docker_compose_template.services.app, local.container, {
        for key, val in local.docker_compose_template.services.app : key =>
        can(tolist(val)) && contains(keys(local.container), key)
        ? try(setunion(val, lookup(local.container, key, [])), val)
        : lookup(local.container, key, val)
      })
    }
    networks = {
      default = {
        external = {
          name = "$${DOCKER_NETWORK}"
        }
      }
    }
  }

  docker_compose_yaml = yamlencode(local.docker_compose)
}

/* ========================================================================== */
/* CLOUD-INIT CONFIG                                                          */
/* ========================================================================== */

// Collate all files to be copied to the server on start-up

locals {
  files = concat(
    [
      {
        filename = ".env"
        content  = base64encode(join("\n", [for k, v in local.environment : "${k}=${v}" if v != null]))
      },
      {
        filename = "docker-compose.caddy.yaml"
        content  = filebase64("${local.template_dir}/docker-compose.caddy.yaml")
      },
    ],

    # Configuration and scripts relating to the webhook service and its endpoints (only if enabled).
    var.enable_webhook ? [
      { filename = "docker-compose.webhook.yaml"
      content = filebase64("${local.template_dir}/docker-compose.webhook.yaml") },
      {
        filename = ".webhook/hooks.json"
        content  = filebase64("${local.template_dir}/webhook/hooks.json")
      },
      {
        filename = ".webhook/update-env.sh"
        content  = filebase64("${local.template_dir}/webhook/update-env.sh")
      }
    ] : [],

    # User-provided docker-compose*.yaml files.
    # If no docker-compose.yaml files are present, one will be generated
    # automatically using the default template and merged with the values specified
    # in `var.container`.
    coalescelist(
      [for f in var.files : f if can(regex(local.file_regex, f.filename))],
      [{ filename = "docker-compose.yaml", content = base64encode(local.docker_compose_yaml) }]
    ),

    # Other user files
    [for f in var.files : f if !can(regex(local.file_regex, f.filename))]
  )

  # From the list above, identify all docker-compose*.yaml files.
  # This list will be used to generate separate systemd unit files for each service.
  docker_compose_files = [
    for f in local.files : merge(regex(local.file_regex, f.filename), f)
    if can(regex(local.file_regex, f.filename))
  ]

}

// Generate cloud-init config

data "cloudinit_config" "config" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "cloud-init.yaml"
    merge_type   = "list(append)+dict(no_replace,recurse_list)+str()"
    content_type = "text/cloud-config"
    content = templatefile("${local.template_dir}/cloud-config.yaml", {
      files                = local.files
      docker_compose_files = local.docker_compose_files
      login                = local.login
      image                = local.image
    })
  }

  # Add any additional cloud-init configuration or scripts provided by the user
  dynamic "part" {
    for_each = var.cloudinit_part
    content {
      merge_type   = "list(append)+dict(no_replace,recurse_list)+str()"
      content_type = part.value.content_type
      content      = part.value.content
    }
  }
}
