---
name: dotnet-recommended
description: House conventions for .NET 10 / C# 14 work — library choices, minimal API and module layout, testing, and the build loop. Use when writing or changing .NET code.
---

# .NET conventions

These are choices, not general .NET advice. In an existing codebase, its conventions win over this list.

## Loop

- After code changes: `dotnet format`, `dotnet build`, `dotnet test`. Fix what they report.
- Never hand-edit or delete EF migrations. Change the model and generate a new one.

## Code

- No backwards compatibility: remove deprecated paths, don't add fallbacks or defensive checks that hide bugs. Fix root causes.
- New code may use C# 14 (extension blocks, `field`, `?.` assignment). Don't rewrite existing code to adopt them.
- `DateTime.UtcNow`, never `DateTime.Now`.

## APIs

- Minimal APIs, not MVC. Return `TypedResults`, not `Results`.
- Feature folders: `src/Features/<Module>/<Module>Module.cs` registers DI and endpoints; one file per endpoint (request, handler, response). `Shared/` is cross-cutting only.
- Modules talk through public APIs or events, never another module's `DbContext`.
- Errors: `AddProblemDetails()` + `UseExceptionHandler()`. Expected domain failures return `ErrorOr<T>`; exceptions are for the unexpected.

## Libraries

| Need | Use |
|---|---|
| Validation | Built-in `AddValidation()`; FluentValidation only when rules outgrow attributes |
| Request handling | Handlers registered in DI per vertical slice; no mediator library |
| HTTP resilience | `AddStandardResilienceHandler()`, not hand-built Polly pipelines |
| Options | `.BindConfiguration(...).ValidateDataAnnotations().ValidateOnStart()` |
| Logging | Serilog |

## Tests

- xUnit v3 (`dotnet new install xunit.v3.templates`, then `dotnet new xunit3`).
- Integration tests through `WebApplicationFactory<Program>`.
