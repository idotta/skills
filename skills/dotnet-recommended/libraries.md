# Key Libraries Reference

## Mediator - CQRS / Mediator Pattern

The mediator pattern is great for implementing cross cutting concerns (logging, metrics, etc) and avoiding "fat" constructors due to lots of injected services.

**Docs:** [Mediator with documentation](https://github.com/martinothamar/Mediator)

### Installation
```
dotnet add package Mediator.SourceGenerator --version 3.0.*
dotnet add package Mediator.Abstractions --version 3.0.*
```

### Registration

```csharp
using Mediator;
using Microsoft.Extensions.DependencyInjection;
using System;

var services = new ServiceCollection(); // Most likely IServiceCollection comes from IHostBuilder/Generic host abstraction in Microsoft.Extensions.Hosting

services.AddMediator();
using var serviceProvider = services.BuildServiceProvider();
```

### Create IRequest type

```csharp
services.AddMediator((MediatorOptions options) => options.Assemblies = [typeof(Ping)]);
using var serviceProvider = services.BuildServiceProvider();
var mediator = serviceProvider.GetRequiredService<IMediator>();
var ping = new Ping(Guid.NewGuid());
var pong = await mediator.Send(ping);
Debug.Assert(ping.Id == pong.Id);

// ...

public sealed record Ping(Guid Id) : IRequest<Pong>;

public sealed record Pong(Guid Id);

public sealed class PingHandler : IRequestHandler<Ping, Pong>
{
    public ValueTask<Pong> Handle(Ping request, CancellationToken cancellationToken)
    {
        return new ValueTask<Pong>(new Pong(request.Id));
    }
}
```

---

## FluentValidation

```csharp
// Installation
// dotnet add package FluentValidation.DependencyInjectionExtensions

// Registration
builder.Services.AddValidatorsFromAssemblyContaining<Program>();

// Validator
public class CreateOrderValidator : AbstractValidator<CreateOrderCommand>
{
    public CreateOrderValidator()
    {
        RuleFor(x => x.CustomerId).GreaterThan(0);
        RuleFor(x => x.Items).NotEmpty().WithMessage("Order must have items");
        RuleForEach(x => x.Items).SetValidator(new OrderItemValidator());
    }
}

// With MediatR pipeline
public class ValidationBehavior<TRequest, TResponse>(IEnumerable<IValidator<TRequest>> validators)
    : IPipelineBehavior<TRequest, TResponse> where TRequest : notnull
{
    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken ct)
    {
        var context = new ValidationContext<TRequest>(request);
        var failures = validators
            .Select(v => v.Validate(context))
            .SelectMany(r => r.Errors)
            .Where(f => f != null)
            .ToList();

        if (failures.Count != 0)
            throw new ValidationException(failures);

        return await next();
    }
}
```

**Docs:** [FluentValidation Documentation](https://docs.fluentvalidation.net/en/latest/)

---

## ErrorOr - Result Pattern

```csharp
// Installation
// dotnet add package ErrorOr

// Define errors
public static class UserErrors
{
    public static Error NotFound(int id) => Error.NotFound("User.NotFound", $"User {id} not found");
    public static Error DuplicateEmail => Error.Conflict("User.DuplicateEmail", "Email already exists");
}

// Service returning ErrorOr
public async Task<ErrorOr<User>> GetUserAsync(int id)
{
    var user = await _db.Users.FindAsync(id);
    return user is null
        ? UserErrors.NotFound(id)
        : user;
}

// Endpoint handling
app.MapGet("/users/{id}", async (int id, IUserService svc) =>
{
    var result = await svc.GetUserAsync(id);
    return result.Match(
        user => TypedResults.Ok(user),
        errors => errors.First().Type switch
        {
            ErrorType.NotFound => TypedResults.NotFound(),
            ErrorType.Conflict => TypedResults.Conflict(),
            ErrorType.Validation => TypedResults.BadRequest(errors),
            _ => TypedResults.Problem()
        }
    );
});

// Chaining operations
public async Task<ErrorOr<OrderConfirmation>> CreateOrderAsync(CreateOrderRequest request)
{
    return await ValidateRequest(request)
        .ThenAsync(req => CreateOrder(req))
        .ThenAsync(order => SendConfirmation(order));
}
```

**Docs:** [ErrorOr README](https://github.com/amantinband/error-or)

---

## Polly - Resilience

```csharp
// Installation
// dotnet add package Microsoft.Extensions.Http.Resilience

// Already covered in infrastructure.md, here's advanced usage:

// Custom resilience pipeline
builder.Services.AddResiliencePipeline("custom", builder =>
{
    builder
        .AddRetry(new RetryStrategyOptions
        {
            MaxRetryAttempts = 3,
            Delay = TimeSpan.FromSeconds(1),
            BackoffType = DelayBackoffType.Exponential,
            ShouldHandle = new PredicateBuilder().Handle<HttpRequestException>()
        })
        .AddCircuitBreaker(new CircuitBreakerStrategyOptions
        {
            FailureRatio = 0.5,
            SamplingDuration = TimeSpan.FromSeconds(10),
            MinimumThroughput = 10,
            BreakDuration = TimeSpan.FromSeconds(30)
        })
        .AddTimeout(TimeSpan.FromSeconds(10));
});

// Usage
public class MyService(ResiliencePipelineProvider<string> pipelineProvider)
{
    public async Task<string> GetDataAsync()
    {
        var pipeline = pipelineProvider.GetPipeline("custom");
        return await pipeline.ExecuteAsync(async ct =>
        {
            // Your operation here
            return await FetchDataAsync(ct);
        });
    }
}
```

**Docs:** [Polly Documentation](https://www.pollydocs.org/)

---

## Serilog - Structured Logging

```csharp
// Installation
// dotnet add package Serilog.AspNetCore
// dotnet add package Serilog.Sinks.Console
// dotnet add package Serilog.Sinks.Seq

// Configuration
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .MinimumLevel.Override("Microsoft.AspNetCore", LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .Enrich.WithEnvironmentName()
    .Enrich.WithCorrelationId()
    .WriteTo.Console(new CompactJsonFormatter())
    .WriteTo.Seq("http://localhost:5341")
    .CreateLogger();

builder.Host.UseSerilog();

// Request logging
app.UseSerilogRequestLogging(options =>
{
    options.EnrichDiagnosticContext = (ctx, httpCtx) =>
    {
        ctx.Set("UserId", httpCtx.User.FindFirstValue("sub"));
    };
});

// Structured logging
logger.LogInformation("Order {OrderId} created for {CustomerId} with {ItemCount} items",
    order.Id, order.CustomerId, order.Items.Count);
```

**Docs:** [Serilog Wiki](https://github.com/serilog/serilog/wiki)

---

## Quick Reference Table

| Library | Purpose | NuGet Package |
|---------|---------|---------------|
| Mediator | Mediator pattern | `Mediator.Abstractions, Mediator.SourceGenerator` |
| FluentValidation | Validation rules | `FluentValidation.DependencyInjectionExtensions` |
| ErrorOr | Result pattern | `ErrorOr` |
| Polly | Resilience | `Microsoft.Extensions.Http.Resilience` |
| Serilog | Structured logging | `Serilog.AspNetCore` |
| Bogus | Fake data | `Bogus` |
| Humanizer | String manipulation | `Humanizer` |