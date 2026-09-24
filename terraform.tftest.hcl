mock_provider "aws" {
}

run "origin_needs_exactly_one_config" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name = "my-bucket.s3.amazonaws.com"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
  }

  expect_failures = [var.origins]
}

run "origin_rejects_both_configs" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
        custom_origin_config = {
          origin_protocol_policy = "https-only"
        }
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
  }

  expect_failures = [var.origins]
}

run "geo_restriction_rejects_bad_type" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
    geo_restriction = {
      restriction_type = "sideways"
    }
  }

  expect_failures = [var.geo_restriction]
}

run "viewer_certificate_rejects_non_us_east_1_arn" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
    viewer_certificate = {
      acm_certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/abc123"
    }
  }

  expect_failures = [var.viewer_certificate]
}

run "s3_origin_renders_oac_no_custom_config" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.resource.origin) == 1
    error_message = "One origins entry should render exactly one origin block."
  }

  assert {
    condition     = anytrue([for o in aws_cloudfront_distribution.resource.origin : o.origin_access_control_id == "E1EXAMPLE"])
    error_message = "origin_access_control_id should pass through unchanged."
  }

  assert {
    condition     = alltrue([for o in aws_cloudfront_distribution.resource.origin : length(o.custom_origin_config) == 0])
    error_message = "An S3/OAC origin should have no custom_origin_config block."
  }
}

run "custom_origin_renders_config_with_defaults" {
  command = plan

  variables {
    origins = {
      alb = {
        domain_name = "internal-alb-123.us-east-1.elb.amazonaws.com"
        custom_origin_config = {
          origin_protocol_policy = "https-only"
        }
      }
    }
    default_cache_behavior = {
      target_origin_id = "alb"
    }
  }

  assert {
    condition     = alltrue([for o in aws_cloudfront_distribution.resource.origin : length(o.custom_origin_config) == 1])
    error_message = "A custom origin should render exactly one custom_origin_config block."
  }

  assert {
    condition     = anytrue([for o in aws_cloudfront_distribution.resource.origin : anytrue([for c in o.custom_origin_config : c.http_port == 80 && c.https_port == 443])])
    error_message = "custom_origin_config's http_port/https_port should default to 80/443."
  }
}

run "default_cache_behavior_uses_caching_optimized_by_default" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.resource.default_cache_behavior[0].cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6"
    error_message = "cache_policy_id should default to AWS's managed CachingOptimized policy."
  }
}

run "ordered_cache_behaviors_render_in_order" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
      api = {
        domain_name = "api.internal.example.com"
        custom_origin_config = {
          origin_protocol_policy = "https-only"
        }
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
    ordered_cache_behaviors = [
      {
        path_pattern     = "/api/*"
        target_origin_id = "api"
        cache_policy_id  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      }
    ]
  }

  assert {
    condition     = length(aws_cloudfront_distribution.resource.ordered_cache_behavior) == 1
    error_message = "One ordered_cache_behaviors entry should render exactly one ordered_cache_behavior block."
  }

  assert {
    condition     = aws_cloudfront_distribution.resource.ordered_cache_behavior[0].path_pattern == "/api/*"
    error_message = "path_pattern should pass through unchanged."
  }
}

run "geo_restriction_null_defaults_to_none" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.resource.restrictions[0].geo_restriction[0].restriction_type == "none"
    error_message = "geo_restriction left null should render restriction_type = 'none'."
  }
}

run "geo_restriction_passes_through" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
    geo_restriction = {
      restriction_type = "whitelist"
      locations        = ["US", "CA"]
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.resource.restrictions[0].geo_restriction[0].restriction_type == "whitelist"
    error_message = "geo_restriction.restriction_type should pass through unchanged."
  }

  assert {
    condition     = toset(aws_cloudfront_distribution.resource.restrictions[0].geo_restriction[0].locations) == toset(["US", "CA"])
    error_message = "geo_restriction.locations should pass through unchanged."
  }
}

run "no_viewer_certificate_uses_default_certificate" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.resource.viewer_certificate[0].cloudfront_default_certificate == true
    error_message = "No viewer_certificate given should default to the shared cloudfront_default_certificate."
  }
}

run "viewer_certificate_passes_through" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
    aliases = ["cdn.example.com"]
    viewer_certificate = {
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.resource.viewer_certificate[0].cloudfront_default_certificate == false
    error_message = "A viewer_certificate given should not use cloudfront_default_certificate."
  }

  assert {
    condition     = aws_cloudfront_distribution.resource.viewer_certificate[0].acm_certificate_arn == "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
    error_message = "acm_certificate_arn should pass through unchanged."
  }

  assert {
    condition     = aws_cloudfront_distribution.resource.viewer_certificate[0].ssl_support_method == "sni-only"
    error_message = "ssl_support_method should default to sni-only."
  }
}

run "custom_error_responses_render" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
    custom_error_responses = [
      {
        error_code         = 404
        response_code      = 200
        response_page_path = "/index.html"
      }
    ]
  }

  assert {
    condition     = length(aws_cloudfront_distribution.resource.custom_error_response) == 1
    error_message = "One custom_error_responses entry should render exactly one custom_error_response block."
  }

  assert {
    condition     = anytrue([for r in aws_cloudfront_distribution.resource.custom_error_response : r.response_page_path == "/index.html"])
    error_message = "response_page_path should pass through unchanged."
  }
}

run "logging_config_null_disables_logging" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.resource.logging_config) == 0
    error_message = "logging_config left null should render no logging_config block."
  }
}

run "logging_config_passes_through" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
    logging_config = {
      bucket = "my-logs.s3.amazonaws.com"
      prefix = "cf/"
    }
  }

  assert {
    condition     = length(aws_cloudfront_distribution.resource.logging_config) == 1
    error_message = "logging_config given should render exactly one logging_config block."
  }

  assert {
    condition     = aws_cloudfront_distribution.resource.logging_config[0].bucket == "my-logs.s3.amazonaws.com"
    error_message = "logging_config.bucket should pass through unchanged."
  }
}

run "retain_on_delete_and_price_class_pass_through" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
    retain_on_delete = true
    price_class      = "PriceClass_100"
  }

  assert {
    condition     = aws_cloudfront_distribution.resource.retain_on_delete == true
    error_message = "retain_on_delete should pass through unchanged."
  }

  assert {
    condition     = aws_cloudfront_distribution.resource.price_class == "PriceClass_100"
    error_message = "price_class should pass through unchanged."
  }
}

run "readme_s3_origin_example" {
  command = plan

  variables {
    origins = {
      s3 = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
    }
    default_cache_behavior = {
      target_origin_id = "s3"
    }
  }
}

run "readme_alb_origin_with_alias_example" {
  command = plan

  variables {
    aliases = ["cdn.example.com"]
    origins = {
      alb = {
        domain_name = "internal-alb-123.us-east-1.elb.amazonaws.com"
        custom_origin_config = {
          origin_protocol_policy = "https-only"
        }
      }
    }
    default_cache_behavior = {
      target_origin_id       = "alb"
      viewer_protocol_policy = "redirect-to-https"
    }
    viewer_certificate = {
      acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc123"
    }
  }
}

run "readme_spa_with_api_path_example" {
  command = plan

  variables {
    origins = {
      site = {
        domain_name              = "my-bucket.s3.amazonaws.com"
        origin_access_control_id = "E1EXAMPLE"
      }
      api = {
        domain_name = "internal-alb-123.us-east-1.elb.amazonaws.com"
        custom_origin_config = {
          origin_protocol_policy = "https-only"
        }
      }
    }
    default_cache_behavior = {
      target_origin_id = "site"
    }
    ordered_cache_behaviors = [
      {
        path_pattern             = "/api/*"
        target_origin_id         = "api"
        cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
        origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
      }
    ]
    custom_error_responses = [
      {
        error_code         = 404
        response_code      = 200
        response_page_path = "/index.html"
      }
    ]
  }
}
