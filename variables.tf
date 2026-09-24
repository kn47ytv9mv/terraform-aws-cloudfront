variable "enabled" {
  default     = true
  description = "Whether the distribution accepts and serves traffic."
}

variable "comment" {
  default     = null
  description = "A comment for the distribution."
}

variable "aliases" {
  default     = null
  description = "Alternate domain names (CNAMEs) the distribution responds to, e.g. 'cdn.example.com'. Each one needs to be covered by viewer_certificate's ACM certificate."
}

variable "default_root_object" {
  default     = null
  description = "Object to request from the origin when a viewer requests the root URL (e.g. 'index.html'). If null, the origin's own default applies."
}

variable "is_ipv6_enabled" {
  default     = true
  description = "Whether the distribution serves IPv6 requests."
}

variable "http_version" {
  default     = null
  description = "Maximum HTTP version the distribution supports (e.g. 'http2', 'http2and3'). If null, AWS's own default applies."
}

variable "price_class" {
  default     = null
  description = "Edge locations that serve the distribution's traffic ('PriceClass_100', 'PriceClass_200', or 'PriceClass_All'). Fewer locations costs less but reaches fewer regions with the lowest latency. If null, AWS's own default (PriceClass_All) applies."
}

variable "web_acl_id" {
  default     = null
  description = "ARN of a WAF web ACL to associate with the distribution. This module does not create the WAF ACL itself."
}

variable "retain_on_delete" {
  default     = false
  description = "Whether to disable the distribution instead of deleting it when this module is destroyed. AWS requires a distribution to be disabled before it can be deleted, so this only matters for keeping it around afterward."
}

variable "wait_for_deployment" {
  default     = null
  description = "Whether to wait for the distribution to reach a deployed state before Terraform considers apply complete. If null, AWS's own default (true) applies."
}

variable "origins" {
  default     = {}
  description = <<-EOT
    Origins the distribution can pull content from, keyed by an arbitrary
    origin ID (referenced by default_cache_behavior's and
    ordered_cache_behaviors' target_origin_id). Each entry needs
    domain_name, plus exactly one of custom_origin_config (an ALB, NLB, or
    any custom HTTP(S) origin) or origin_access_control_id (an S3 bucket
    origin, secured with a pre-created aws_cloudfront_origin_access_control
    this module does not manage — pair with a bucket policy granting that
    OAC read access).
  EOT
  type = map(object({
    domain_name              = string
    origin_path              = optional(string)
    origin_access_control_id = optional(string)
    connection_attempts      = optional(number)
    connection_timeout       = optional(number)
    custom_header = optional(list(object({
      name  = string
      value = string
    })), [])
    custom_origin_config = optional(object({
      http_port                = optional(number, 80)
      https_port               = optional(number, 443)
      origin_protocol_policy   = optional(string, "https-only")
      origin_ssl_protocols     = optional(list(string), ["TLSv1.2"])
      origin_keepalive_timeout = optional(number)
      origin_read_timeout      = optional(number)
    }))
  }))

  validation {
    condition = alltrue([
      for k, o in var.origins : (o.custom_origin_config != null) != (o.origin_access_control_id != null)
    ])
    error_message = "Each origins entry needs exactly one of custom_origin_config or origin_access_control_id."
  }
}

variable "default_cache_behavior" {
  description = <<-EOT
    The cache behavior applied when no ordered_cache_behaviors entry's
    path_pattern matches. target_origin_id must be a key in origins.
    cache_policy_id defaults to AWS's managed 'CachingOptimized' policy —
    override it (or set origin_request_policy_id /
    response_headers_policy_id) to change what varies the cache key.
  EOT
  type = object({
    target_origin_id           = string
    viewer_protocol_policy     = optional(string, "redirect-to-https")
    allowed_methods            = optional(list(string), ["GET", "HEAD"])
    cached_methods             = optional(list(string), ["GET", "HEAD"])
    compress                   = optional(bool, true)
    cache_policy_id            = optional(string, "658327ea-f89d-4fab-a63d-7e88639e58f6")
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
  })
}

variable "ordered_cache_behaviors" {
  default     = []
  description = "Additional cache behaviors evaluated in order before default_cache_behavior, each matched against a path_pattern (e.g. '/api/*'). Same shape as default_cache_behavior, plus path_pattern."
  type = list(object({
    path_pattern               = string
    target_origin_id           = string
    viewer_protocol_policy     = optional(string, "redirect-to-https")
    allowed_methods            = optional(list(string), ["GET", "HEAD"])
    cached_methods             = optional(list(string), ["GET", "HEAD"])
    compress                   = optional(bool, true)
    cache_policy_id            = optional(string, "658327ea-f89d-4fab-a63d-7e88639e58f6")
    origin_request_policy_id   = optional(string)
    response_headers_policy_id = optional(string)
  }))
}

variable "geo_restriction" {
  default     = null
  description = "Restrict the distribution by viewer country. restriction_type is 'whitelist', 'blacklist', or 'none'; locations is a list of ISO 3166-1-alpha-2 country codes, required unless restriction_type is 'none'. If null, no restriction applies."
  type = object({
    restriction_type = string
    locations        = optional(list(string), [])
  })

  validation {
    condition     = var.geo_restriction == null || contains(["whitelist", "blacklist", "none"], var.geo_restriction.restriction_type)
    error_message = "geo_restriction.restriction_type must be 'whitelist', 'blacklist', or 'none'."
  }
}

variable "viewer_certificate" {
  default     = null
  description = "Custom domain HTTPS certificate. acm_certificate_arn must be an ACM certificate in us-east-1 regardless of the distribution's own region (a real AWS requirement) — pair with terraform-aws-acm-certificate. If null, the shared *.cloudfront.net certificate is used, and aliases should be left unset."
  type = object({
    acm_certificate_arn      = string
    ssl_support_method       = optional(string, "sni-only")
    minimum_protocol_version = optional(string, "TLSv1.2_2021")
  })

  validation {
    condition     = var.viewer_certificate == null || can(regex("^arn:aws:acm:us-east-1:", var.viewer_certificate.acm_certificate_arn))
    error_message = "viewer_certificate.acm_certificate_arn must be an ACM certificate in us-east-1, regardless of the distribution's own region — a real AWS/CloudFront requirement, not a default."
  }
}

variable "custom_error_responses" {
  default     = []
  description = "Custom responses for specific origin error codes, e.g. serving a SPA's index.html for a 403/404 instead of the origin's own error page."
  type = list(object({
    error_code            = number
    response_code         = optional(number)
    response_page_path    = optional(string)
    error_caching_min_ttl = optional(number)
  }))
}

variable "logging_config" {
  default     = null
  description = "Access logging to an S3 bucket. bucket is the bucket's full domain name (e.g. 'my-logs.s3.amazonaws.com', not just the bucket name) — pair with terraform-aws-s3's bucket output plus '.s3.amazonaws.com'. If null, access logging is disabled."
  type = object({
    bucket          = string
    prefix          = optional(string)
    include_cookies = optional(bool, false)
  })
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to the distribution."
}
