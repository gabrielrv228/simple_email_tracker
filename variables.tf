variable "bot_token" {
  description = "Telegram bot token used for authentication when sending messages."
  type        = string
  nullable    = false
}

variable "chat_id" {
  description = "Telegram chat ID (numeric) that the bot will post notifications to."
  type        = string
  nullable    = false

}

variable "pixel_img" {
  description = "Base64‑encoded PNG (or other image) that will be sent as a tracking pixel once the user opens the email."
  type        = string
  nullable    = false
}

variable "aws_region" {
  description = "The region you want to deploy to"
  type        = string
  nullable    = false
  default = "us-east-1"
}
