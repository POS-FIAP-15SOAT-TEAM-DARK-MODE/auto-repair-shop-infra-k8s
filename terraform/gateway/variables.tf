variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "auto-repair-shop"
}

variable "state_bucket" {
  description = "S3 bucket holding the remote state — the same bucket created by this repo's bootstrap state. Passed by the workflow, derived from the AWS account id."
  type        = string
}

# Unused here — declared only so this layer accepts the same blanket
# -var flag the workflow passes to every layer, without needing a
# layer-specific case in the workflow script.
variable "manage_iam" {
  type    = bool
  default = true
}

variable "auth_route_rate_limit" {
  description = "Requests/sec allowed on the auth routes (login endpoints), steady-state."
  type        = number
  default     = 5
}

variable "auth_route_burst_limit" {
  type    = number
  default = 10
}

variable "default_rate_limit" {
  description = "Requests/sec allowed on all other routes, steady-state."
  type        = number
  default     = 25
}

variable "default_burst_limit" {
  type    = number
  default = 50
}
