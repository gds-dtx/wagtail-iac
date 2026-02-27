resource "aws_route53_zone" "_zone" {
  # this is set in the providers block when calling this module
  provider = aws.dns-account

  count = var.bootstrap_step >= 1 && var.route53_zone_id == "" ? 1 : 0
  name  = var.wagtail_domain

  tags = {
    Name = "${local.task_name}-route53-zone"
  }
}

data "aws_route53_zone" "zone" {
  # this is set in the providers block when calling this module
  provider = aws.dns-account

  zone_id = var.route53_zone_id != "" ? var.route53_zone_id : aws_route53_zone._zone[0].zone_id
}

resource "aws_route53_record" "alb" {
  # this is set in the providers block when calling this module
  provider = aws.dns-account

  count = var.bootstrap_step >= 1 ? 1 : 0

  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "alb.${var.wagtail_domain}"
  type    = "CNAME"
  ttl     = 300

  records = [data.aws_lb.alb.dns_name]
}

resource "aws_route53_record" "wagtail_a" {
  # this is set in the providers block when calling this module
  provider = aws.dns-account

  count = var.bootstrap_step >= 3 ? 1 : 0

  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.wagtail_domain
  type    = "A"

  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.this[0].domain_name
    zone_id                = aws_cloudfront_distribution.this[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wagtail_aaaa" {
  # this is set in the providers block when calling this module
  provider = aws.dns-account

  count = var.bootstrap_step >= 3 ? 1 : 0

  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.wagtail_domain
  type    = "AAAA"

  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.this[0].domain_name
    zone_id                = aws_cloudfront_distribution.this[0].hosted_zone_id
    evaluate_target_health = false
  }
}
