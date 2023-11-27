variable "name" {
  type        = string
  description = "(optional) Specify the name for resources. Default: random name prefix with sudo"
  default     = null
}

variable "cognito_pool" {
  type        = string
  description = "(optional) Specify the Cognito Pool ID. Default: null"
  default     = null
}

variable "visibility_timeout_seconds" {
  type        = number
  description = "(Optional) The visibility timeout for the queue. An integer from 0 to 43200 (12 hours). Default: 105"
  default     = 105
}

variable "delay_seconds" {
  type        = number
  description = "(optional) describe your variable"
  default     = 90
}

variable "max_message_size" {
  type        = number
  description = "(optional) describe your variable"
  default     = 2048
}

variable "message_retention_seconds" {
  type        = number
  description = "(optional) describe your variable"
  default     = 86400
}
variable "receive_wait_time_seconds" {
  type        = number
  description = "(Optional) The time for which a ReceiveMessage call will wait for a message to arrive (long polling) before returning. An integer from 0 to 20 (seconds). Default: 20"
  default     = 20
}
variable "max_receive_count" {
  type        = number
  description = "(optional) describe your variable"
  default     = 4
}

variable "global_tags" {
  type        = map(string)
  description = "(optional) A mapping of tags to assign to the resource."
  default     = {}
}
