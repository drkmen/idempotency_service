# Before you go
Hello mamopay team! 

First, I want to thank you for such an interesting assessment. It's really the most complex so far I've had to deal with.
I was learning a lot during trying to implement your requirements.

Unfortunately, after 6 hours I ended up with a mess and solution I'm not satisfied with. Now let's go step by step.

## Struggles
Because of the time constraint, I had to use AI heavily. I started with asking AI to generate the implementation plan based on the requirements.
You can check `task.md` and `plan.md` for more details. So after I've got the plan, I asked AI to implement it.
Step by step, with milestones. After reaching results, because of lack of time, I had to prompt AI to complete remaining things which I usually do by myself.
Like code refactoring, tests, documentation, etc. That's why I'm not happy with code quality, specs scenarios, errors handling, project structure.

The scope of work was huge, so one of the biggest trade-offs was to try to provide as much reliability as possible in favor of quality.

Probably, this led to the overengineering and for sure to the mess.

I was not able to do testing manually, so I had to completely rely on specs, which in the end were not even able to 
run for some reason(literally nothing happens after running `rspec`), and I had no time to investigate why.

## Trade-offs and decisions
- As I mentioned above, I had to prioritize reliability and completeness of the solution over code quality, tests coverage and project structure.
- Redis was used as a source of truth because it's superfast. But since Redis is not reliable from the perspective of data loss, as a permanent storage, I had to use PostgreSQL.
- .lua scripts were used to implement the business logic because redis executes them as atomic operation.

## What I'd do next
If I had more time, I would do the following:
- Refactor code and improve the project structure
- Introduce observability tools, expired keys cleanup, caching
- Introduce more tests, especially for edge cases and concurrency scenarios
- Improve error handling, logging and responses
- Probably, introduce load balancer, rate limiting, Redis replication or maybe configure Redis to write to disk

## Conclusion
I'm not happy with the result and sorry you have to spend your time reviewing it. Warm humbles, Mihail