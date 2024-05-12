## 1.0.0-beta.1
- Initial release
- TODO Readme.md

## 1.0.0-beta.2
- Small bug fix on accessing unavailable error property in unsafe handling
- Small bug fix on handling error in unsafe execution
- TODO @tsavo-at-pieces README.md

## 1.0.0-beta.3
- Error catching now supports both anticipated errors and unknown errors
- Small bug fix on handling error in unsafe execution
- Small adjustments leveraging records as metadata on single-set properties
- Additional unit testing
- Helper rethrow_() method for rethrowing internally caught errors to the outside world 
- Better handling of Futures that are returned from the callable() callback that is internally executed
- GitHub Actions CI/CD for Testing on MacOS (x86_64 and arm64), Linux (x86_64)
- TODO: @tsavo-at-pieces README.md
- TODO: Leveraging NamedLocks directly i.e. outside the NamedLock.guard() function
- TODO: WindowsNamedLock implementation

## 1.0.0-beta.4
- ~~TODO~~ DONE: @tsavo-at-pieces README.md
- ~~TODO~~ DONE: WindowsNamedLock implementation
- Updated runtime_native_semaphores dependency to 1.0.0-beta.6
- All tests passing on MacOS (x86_64 and arm64), Linux (x86_64), Windows (x86_64) 🎉
- TODO: Leveraging NamedLocks directly i.e. outside the NamedLock.guard() function
- TODO: Add explicit NamedLocks.guardAsync() method for explicit async executions
- TODO: In code dartdoc comments for pub.dev API documentation

