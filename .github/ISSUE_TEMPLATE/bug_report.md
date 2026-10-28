---
name: Bug Report
about: Report a route audit discrepancy, false positive, false negative, or runtime issue
title: "[Bug]: "
labels: ["bug"]
assignees: ""
---

### Describe the Bug
A clear and concise description of the unexpected behavior.

### Type of Issue
- [ ] Audit false positive (flagged an authorized route as missing or invalid)
- [ ] Audit false negative (missed an unmapped route or exposed action)
- [ ] Behavioral persona probe discrepancy
- [ ] Mounted engine route resolution error
- [ ] Runtime request authorization error (unexpected status code or header)
- [ ] CLI / reporting formatting issue

### Minimal Reproduction
1. Rails version:
2. Ruby version:
3. Minimal Controller & Route snippet:

```ruby
# config/routes.rb or app/controllers/...
```

4. Minimal configuration (`config/mecha_authorize.yml`):

```yaml
# Relevant config snippet
```

### Expected Behavior
What should the audit or runtime have reported instead?
