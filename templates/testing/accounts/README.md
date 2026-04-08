# Accounts Test Template

## Target Structure

```text
internal/handler/*_test.go
internal/service/*_test.go
internal/repository/*_test.go
test/integration/
```

## Core Flows

- login and authentication
- session or token validation
- current user fetch
- APIs required by Xworkmate desktop first screen

## Layer Responsibilities

### handler tests

- status code
- request validation
- error body

### service tests

- business branches
- permission decisions
- state transitions

### repository tests

- query and write contracts
- empty, duplicate, and edge-case data

### integration tests

- minimal API-to-persistence closed loop

## Generated Draft Inputs

Every generated draft should include:

- input condition
- fixture dependency
- expected status code and response field
- regression-first note for the failing branch
