# Intent Contract Example

仅在需要产出完整 intent JSON 时读取。尖括号内容都必须由目标 App 的源码证据替换；不要把本模板中的业务词当成默认页面或默认行为。

```json
{
  "id": "<flow>-<outcome>",
  "flow": "<flow>",
  "intent": "<scenario and expected outcome>",
  "prompt": "<runtime steps expressed with visible labels and roles>",
  "business_points": [
    "<ViewModel>.<submit>(validated input)",
    "<Service>.<request>(business branch)",
    "<ViewController>.<renderOutcome>(visible terminal state)"
  ],
  "files": [
    "<relative-source-path>"
  ],
  "depends_on": {
    "seed_data": "<source-backed prerequisite>"
  },
  "pass_criteria": [
    {
      "mode": "textExists",
      "value": "<stable terminal text>",
      "description": "<why this proves the outcome>",
      "timing": "<source-backed timing>"
    },
    {
      "mode": "targetGone",
      "value": "<role and visible label of a target present at baseline>",
      "description": "<why disappearance is required>"
    }
  ],
  "fail_criteria": [
    {
      "mode": "alert",
      "value": "<stable alert title/message or null>",
      "description": "<why this alert contradicts the expected outcome>"
    },
    {
      "mode": "textExists",
      "value": "<stable failure text>",
      "description": "<why this is a terminal failure>"
    }
  ],
  "timing": "<overall source-backed timing>",
  "source_refs": [
    "<relative-file>:<symbol>"
  ]
}
```

`pass_criteria` 是合取关系：全部满足才算通过。`fail_criteria` 是析取关系：任一出现即失败。`targetGone` 只有在执行层先确认目标曾存在时才能作为终态证据。`alert` 不属于 `ui_waitAny` 的 mode；执行层必须通过 `ui_inspect.alert` 验证。
