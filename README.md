# terraform-aws-cloudfront

Terraform module for a CloudFront distribution.

## Cost

CloudFront bills per GB served and per request, both varying by the
viewer's edge location — `price_class` trades reach for cost by
limiting which edge locations serve the distribution. A distribution
itself has no idle charge. See AWS's
[CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/) page
for current rates.

## Design

Each `origins` entry needs exactly one of `custom_origin_config` (an
ALB, NLB, or any custom HTTP(S) origin) or `origin_access_control_id`
(an S3 bucket origin). This module only supports the modern
Origin Access Control (OAC) path for S3 — not the legacy Origin Access
Identity (OAI) — matching current AWS guidance. It creates neither the
OAC resource itself nor the S3 bucket policy granting it read access;
pair with
[`terraform-aws-s3`](https://github.com/kn47ytv9mv/terraform-aws-s3)
and your own `aws_cloudfront_origin_access_control` resource.

`default_cache_behavior` and each `ordered_cache_behaviors` entry
default `cache_policy_id` to AWS's managed `CachingOptimized` policy —
override it, or set `origin_request_policy_id` /
`response_headers_policy_id`, to change what varies the cache key.
`ordered_cache_behaviors` is a list, not a map: AWS evaluates path
patterns in order, first match wins, so entry order is meaningful.

`viewer_certificate.acm_certificate_arn` must be an ACM certificate in
**us-east-1**, regardless of the distribution's own region — a real
AWS requirement, not a default. Pair with
[`terraform-aws-acm-certificate`](https://github.com/kn47ytv9mv/terraform-aws-acm-certificate)
provisioned against a us-east-1 provider. Leaving `viewer_certificate`
null uses the shared `*.cloudfront.net` certificate, in which case
`aliases` should be left unset too — AWS rejects a custom alias
without a matching certificate.

## Usage

An S3 bucket origin, secured with OAC:

```hcl
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

module "distribution" {
  source = "kn47ytv9mv/cloudfront/aws"

  origins = {
    site = {
      domain_name               = module.bucket.bucket_regional_domain_name
      origin_access_control_id  = aws_cloudfront_origin_access_control.site.id
    }
  }

  default_cache_behavior = {
    target_origin_id = "site"
  }
}
```

Or directly from this repository, a custom-domain distribution in
front of an ALB, with a path-based API route:

```hcl
module "distribution" {
  source = "github.com/kn47ytv9mv/terraform-aws-cloudfront"

  aliases = ["www.example.com"]

  origins = {
    site = {
      domain_name               = module.bucket.bucket_regional_domain_name
      origin_access_control_id  = aws_cloudfront_origin_access_control.site.id
    }
    api = {
      domain_name = module.alb.dns_name
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
      path_pattern              = "/api/*"
      target_origin_id          = "api"
      cache_policy_id           = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
      origin_request_policy_id  = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader
    }
  ]

  viewer_certificate = {
    acm_certificate_arn = module.certificate.arn
  }
}
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.3 |
| aws | ~> 6.61 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| enabled | Whether the distribution accepts and serves traffic. | `true` | no |
| comment | A comment for the distribution. | `null` | no |
| aliases | Alternate domain names (CNAMEs) the distribution responds to, e.g. 'cdn.example.com'. Each one needs to be covered by viewer_certificate's ACM certificate. | `null` | no |
| default_root_object | Object to request from the origin when a viewer requests the root URL (e.g. 'index.html'). If null, the origin's own default applies. | `null` | no |
| is_ipv6_enabled | Whether the distribution serves IPv6 requests. | `true` | no |
| http_version | Maximum HTTP version the distribution supports (e.g. 'http2', 'http2and3'). If null, AWS's own default applies. | `null` | no |
| price_class | Edge locations that serve the distribution's traffic ('PriceClass_100', 'PriceClass_200', or 'PriceClass_All'). Fewer locations costs less but reaches fewer regions with the lowest latency. If null, AWS's own default (PriceClass_All) applies. | `null` | no |
| web_acl_id | ARN of a WAF web ACL to associate with the distribution. This module does not create the WAF ACL itself. | `null` | no |
| retain_on_delete | Whether to disable the distribution instead of deleting it when this module is destroyed. AWS requires a distribution to be disabled before it can be deleted, so this only matters for keeping it around afterward. | `false` | no |
| wait_for_deployment | Whether to wait for the distribution to reach a deployed state before Terraform considers apply complete. If null, AWS's own default (true) applies. | `null` | no |
| origins | Origins the distribution can pull content from, keyed by an arbitrary origin ID (referenced by default_cache_behavior's and ordered_cache_behaviors' target_origin_id). Each entry needs domain_name, plus exactly one of custom_origin_config (an ALB, NLB, or any custom HTTP(S) origin) or origin_access_control_id (an S3 bucket origin, secured with a pre-created aws_cloudfront_origin_access_control this module does not manage — pair with a bucket policy granting that OAC read access). | `{}` | no |
| default_cache_behavior | The cache behavior applied when no ordered_cache_behaviors entry's path_pattern matches. target_origin_id must be a key in origins. cache_policy_id defaults to AWS's managed 'CachingOptimized' policy — override it (or set origin_request_policy_id / response_headers_policy_id) to change what varies the cache key. | n/a | yes |
| ordered_cache_behaviors | Additional cache behaviors evaluated in order before default_cache_behavior, each matched against a path_pattern (e.g. '/api/*'). Same shape as default_cache_behavior, plus path_pattern. | `[]` | no |
| geo_restriction | Restrict the distribution by viewer country. restriction_type is 'whitelist', 'blacklist', or 'none'; locations is a list of ISO 3166-1-alpha-2 country codes, required unless restriction_type is 'none'. If null, no restriction applies. | `null` | no |
| viewer_certificate | Custom domain HTTPS certificate. acm_certificate_arn must be an ACM certificate in us-east-1 regardless of the distribution's own region (a real AWS requirement) — pair with terraform-aws-acm-certificate. If null, the shared *.cloudfront.net certificate is used, and aliases should be left unset. | `null` | no |
| custom_error_responses | Custom responses for specific origin error codes, e.g. serving a SPA's index.html for a 403/404 instead of the origin's own error page. | `[]` | no |
| logging_config | Access logging to an S3 bucket. bucket is the bucket's full domain name (e.g. 'my-logs.s3.amazonaws.com', not just the bucket name) — pair with terraform-aws-s3's bucket output plus '.s3.amazonaws.com'. If null, access logging is disabled. | `null` | no |
| tags | A map of tags to assign to the distribution. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The ID of the distribution. |
| arn | The ARN of the distribution. |
| domain_name | The distribution's own *.cloudfront.net domain name — point a Route53 alias record here, or a CNAME/ALIAS from an alias in var.aliases. |
| hosted_zone_id | Route53 hosted zone ID for the distribution's domain_name, for an alias record's zone_id. Identical for every CloudFront distribution — an AWS constant. |
| status | The distribution's deployment status (e.g. 'Deployed', 'InProgress'). |

## License

MIT — see [LICENSE.md](LICENSE.md).
