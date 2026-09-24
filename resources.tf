resource "aws_cloudfront_distribution" "resource" {
  enabled             = var.enabled
  comment             = var.comment
  aliases             = var.aliases
  default_root_object = var.default_root_object
  is_ipv6_enabled     = var.is_ipv6_enabled
  http_version        = var.http_version
  price_class         = var.price_class
  web_acl_id          = var.web_acl_id
  retain_on_delete    = var.retain_on_delete
  wait_for_deployment = var.wait_for_deployment

  dynamic "origin" {
    for_each = var.origins

    content {
      origin_id                = origin.key
      domain_name              = origin.value.domain_name
      origin_path              = origin.value.origin_path
      origin_access_control_id = origin.value.origin_access_control_id
      connection_attempts      = origin.value.connection_attempts
      connection_timeout       = origin.value.connection_timeout

      dynamic "custom_header" {
        for_each = origin.value.custom_header

        content {
          name  = custom_header.value.name
          value = custom_header.value.value
        }
      }

      dynamic "custom_origin_config" {
        for_each = origin.value.custom_origin_config[*]

        content {
          http_port                = custom_origin_config.value.http_port
          https_port               = custom_origin_config.value.https_port
          origin_protocol_policy   = custom_origin_config.value.origin_protocol_policy
          origin_ssl_protocols     = custom_origin_config.value.origin_ssl_protocols
          origin_keepalive_timeout = custom_origin_config.value.origin_keepalive_timeout
          origin_read_timeout      = custom_origin_config.value.origin_read_timeout
        }
      }
    }
  }

  default_cache_behavior {
    target_origin_id           = var.default_cache_behavior.target_origin_id
    viewer_protocol_policy     = var.default_cache_behavior.viewer_protocol_policy
    allowed_methods            = var.default_cache_behavior.allowed_methods
    cached_methods             = var.default_cache_behavior.cached_methods
    compress                   = var.default_cache_behavior.compress
    cache_policy_id            = var.default_cache_behavior.cache_policy_id
    origin_request_policy_id   = var.default_cache_behavior.origin_request_policy_id
    response_headers_policy_id = var.default_cache_behavior.response_headers_policy_id
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.ordered_cache_behaviors

    content {
      path_pattern               = ordered_cache_behavior.value.path_pattern
      target_origin_id           = ordered_cache_behavior.value.target_origin_id
      viewer_protocol_policy     = ordered_cache_behavior.value.viewer_protocol_policy
      allowed_methods            = ordered_cache_behavior.value.allowed_methods
      cached_methods             = ordered_cache_behavior.value.cached_methods
      compress                   = ordered_cache_behavior.value.compress
      cache_policy_id            = ordered_cache_behavior.value.cache_policy_id
      origin_request_policy_id   = ordered_cache_behavior.value.origin_request_policy_id
      response_headers_policy_id = ordered_cache_behavior.value.response_headers_policy_id
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = coalesce(var.geo_restriction, { restriction_type = "none", locations = [] }).restriction_type
      locations        = coalesce(var.geo_restriction, { restriction_type = "none", locations = [] }).locations
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.viewer_certificate == null
    acm_certificate_arn            = var.viewer_certificate != null ? var.viewer_certificate.acm_certificate_arn : null
    ssl_support_method             = var.viewer_certificate != null ? var.viewer_certificate.ssl_support_method : null
    minimum_protocol_version       = var.viewer_certificate != null ? var.viewer_certificate.minimum_protocol_version : null
  }

  dynamic "custom_error_response" {
    for_each = var.custom_error_responses

    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  dynamic "logging_config" {
    for_each = var.logging_config[*]

    content {
      bucket          = logging_config.value.bucket
      prefix          = logging_config.value.prefix
      include_cookies = logging_config.value.include_cookies
    }
  }

  tags = var.tags
}

output "id" {
  description = "The ID of the distribution."
  value       = aws_cloudfront_distribution.resource.id
}

output "arn" {
  description = "The ARN of the distribution."
  value       = aws_cloudfront_distribution.resource.arn
}

output "domain_name" {
  description = "The distribution's own *.cloudfront.net domain name — point a Route53 alias record here, or a CNAME/ALIAS from an alias in var.aliases."
  value       = aws_cloudfront_distribution.resource.domain_name
}

output "hosted_zone_id" {
  description = "Route53 hosted zone ID for the distribution's domain_name, for an alias record's zone_id. Identical for every CloudFront distribution — an AWS constant."
  value       = aws_cloudfront_distribution.resource.hosted_zone_id
}

output "status" {
  description = "The distribution's deployment status (e.g. 'Deployed', 'InProgress')."
  value       = aws_cloudfront_distribution.resource.status
}
