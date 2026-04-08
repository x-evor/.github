# Xworkmate Test Template

## Target Structure

```text
test/
  helpers/
  widget/
  golden/
integration_test/
patrol_test/
```

## Core Flows

- app bootstrap and shell render
- login and session restore
- primary navigation switch
- settings interaction
- accounts auth dependency

## Layer Responsibilities

### `test/widget/`

- form state
- navigation state
- view model and UI state

### `test/golden/`

- login page baseline
- primary workspace baseline
- settings page baseline

### `integration_test/`

- login success
- navigation flow
- settings save
- failure-state hint

### `patrol_test/`

- native window behavior
- permission dialog
- external link or webview behavior

## Generated Draft Inputs

Every generated draft should include:

- page name
- critical widget keys/selectors
- main assertion
- fake dependency list
- environment assumptions
