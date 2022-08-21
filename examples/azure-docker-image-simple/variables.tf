variable "domain" {
  description = "The domain where the app will be hosted."
  type        = string
}

variable "base_resource_name" {
  type        = string
  description = "Used for resource group, DNS name, etc."
}

variable "location" {
  type        = string
  description = "Azure location to which resources should be deployed."
}
