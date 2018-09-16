---
title: Associated Resources
---

As explained in the [Core Resource Modeling](http://rubyonjets.com/docs/core-resource/) docs, methods like `rate` and `cron` simply perform some wrapper logic and then utlimately call the `resource` method. We'll cover that wrapper logic and expansion process in more details here.

The `rate` method ultimately creates a CloudWatch Event Rule resource. This Event Rule resource is associated with the `dig` Lambda function. Here's the example again:

```ruby
class HardJob < ApplicationJob
  rate "10 hours" # every 10 hours
  def dig
    {done: "digging"}
  end
end
```

What's happens is that Jets takes the `rate` method, performs some wrapper logic, and calls the core `resource` method in the first pass.  The code looks something like this:

```ruby
class HardJob < ApplicationJob
  resource(
    "{namespace}EventsRule": {
      type: "AWS::Events::Rule",
      properties: {
        schedule_expression: "rate(10 hours)",
        state: "ENABLED",
        targets: [{
          arn: "!GetAtt {namespace}LambdaFunction.Arn",
          id: "{namespace}RuleTarget"
        }]
      }
    }
  )
  def dig
    {done: "digging"}
  end
end
```

Jets then replaces the `{namespace}` with an identifier a value that has the class and method that represents the Lambda function. For example:

Before | After
--- | ---
{namespace} | HardJobDig

The final code looks something like this:

```ruby
class HardJob < ApplicationJob
  resource(
    "HardJobDigEventsRule": {
      type: "AWS::Events::Rule",
      properties: {
        schedule_expression: "rate(10 hours)",
        state: "ENABLED",
        targets: [{
          arn: "!GetAtt HardJobDigLambdaFunction.Arn",
          id: "HardJobDigRuleTarget"
        }]
      }
    }
  )
  def dig
    {done: "digging"}
  end
end
```

The `resource` method creates the [AWS::Events::Rule](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-events-rule.html) as a CloudFormation resource. The keys of the Hash structure use the underscore format following Ruby naming convention. As part of CloudFormation template processing, the underscored keys are camelized before deploying to CloudFormation.

<a id="prev" class="btn btn-basic" href="{% link _docs/core-resource.md %}">Back</a>
<a id="next" class="btn btn-primary" href="{% link _docs/shared-resources.md %}">Next Step</a>
<p class="keyboard-tip">Pro tip: Use the <- and -> arrow keys to move back and forward.</p>