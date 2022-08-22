

variable "domain" {
  description = "The domain to deploy applications under."
  type        = string
}

variable "files" {
  description = "User files to be copied to the application's working directory (`/var/app`). The file's content must be provided to Terraform as a base64 encoded string."
  type        = list(object({ filename : string, content : string }))
  default     = []
}

variable "env" {
  description = "List of environment variables (KEY=VAL) to be made available within the application container and also Docker Compose (useful for overriding configuration options)."
  type        = map(string)
  default     = {}
}

variable "container" {
  description = "Object containing the definition of the container to deploy. The key and values from this object are interpolated directly into the Docker Compose file used to run your application, refer to the Docker Compose documentation for more information."
  type        = any
  default     = {}
}

variable "port" {
  description = "The source port on the container for caddy to proxy"
  type        = number
  default     = 80
}

variable "cloudinit_part" {
  description = "Additional cloud-init configuration used to setup and/or customise the instance beyond the defaults provided by this module."
  type        = list(object({ content_type : string, content : string }))
  default     = []
}

variable "enable_webhook" {
  description = "Enabling this feature will expose an endpoint (`/hooks/update-env`) on the server allowing updates to be made to the application's environment variables via a PATCH request. The webhook service will trigger Docker Compose to pull the latest version of the application's container image and restart the service."
  type        = bool
  default     = false
}

variable "image" {
  type    = string
  default = null
}

variable "registry_url" {
  type    = string
  default = null
}

variable "registry_user" {
  type    = string
  default = null
}
variable "registry_password" {
  type      = string
  default   = null
  sensitive = true
}
