/**
Implements logging facilities.

Message logging is a common approach to expose runtime information of a
program. Logging should be easy, but also flexible and powerful, therefore
$(D D) provides a standard interface for logging.

The easiest way to create a log message is to write
$(D import std.logger; log("I am here");). This will print a message to the
standard output pipe. The message will contain the filename, the line number, the
name of the surrounding function, the time and the message.

Copyright: Copyright Robert "burner" Schadek 2013 --
License: $(WEB http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Authors: $(WEB http://www.svs.informatik.uni-oldenburg.de/60865.html, Robert burner Schadek)

-------------
log("Logging to the defaultLogger with its default LogLevel");
loglcf(LogLevel.info, 5 < 6, "%s to the defaultLogger with its LogLevel.info", "Logging");
info("Logging to the defaultLogger with its info LogLevel");
warningc(5 < 6, "Logging to the defaultLogger with its LogLevel.warning if 5 is less than 6");
error("Logging to the defaultLogger with its error LogLevel");
errorf("Logging %s the defaultLogger %s its error LogLevel", "to", "with");
critical("Logging to the"," defaultLogger with its error LogLevel");
fatal("Logging to the defaultLogger with its fatal LogLevel");

auto fLogger = new FileLogger("mylogfile.log");
fLogger.log("Logging to the fileLogger with its default LogLevel");
fLogger.info("Logging to the fileLogger with its default LogLevel");
fLogger.warningc(5 < 6, "Logging to the fileLogger with its LogLevel.warning if 5 is less than 6");
fLogger.warningcf(5 < 6, "Logging to the fileLogger with its LogLevel.warning if %s is %s than 6", 5, "less");
fLogger.critical("Logging to the fileLogger with its info LogLevel");
fLogger.loglc(LogLevel.trace, 5 < 6, "Logging to the fileLogger"," with its default LogLevel if 5 is less than 6");
fLogger.fatal("Logging to the fileLogger with its warning LogLevel");
-------------

Calls to top-level logging functions go to the $(D Logger)
object $(LREF defaultLogger).
$(LI $(D log))
$(LI $(D trace))
$(LI $(D info))
$(LI $(D warning))
$(LI $(D critical))
$(LI $(D fatal))
$(D defaultLogger) can be assigned to a user-specified logger instance
to override the default logging behavior:
-------------
defaultLogger = new FileLogger("defaultlogfile.log");
-------------
Left unchanged, $(D defaultLogger) logs to the standard output pipe
with a default $(D LogLevel) of $(D LogLevel.all).

In addition to the default logger, custom logger instances can be used
to achieve non-default logging behavior:
-------------
auto myLogger = new FileLogger(stderr);
myLogger.log("This log entry is written to the standard error pipe");
log("This log entry is written using the specified default logging behaviour");
-------------

The $(D LogLevel) of a log entry can be specified in one of two ways.
The first is by calling $(D logl) (note the $(D l) suffix)
and passing the $(D LogLevel) explicitly as the first argument.
The second way of setting the $(D LogLevel) of a log entry is by calling any of
$(D trace), $(D info), $(D warning), $(D critical) and $(D fatal), which
implicitly attach their respective log level.

Conditional logging is facilitated by the logging functions
with the $(B c) suffix, which receive a boolean as the first argument;
the entry is only logged when the boolean is true.

Conditional logging can be combined with an explicit $(D LogLevel) by using
the logging functions with the $(B lc) suffix, which take the $(D LogLevel) as
the first and the logging condition as the second argument.

Messages are logged if the $(D LogLevel) of the log message is greater than or
equal to the $(D LogLevel) of the $(D Logger) used, and additionally if the
$(D LogLevel) of the log message is greater or equal to the global $(D LogLevel).
The global $(D LogLevel) is accessible through $(LREF globalLogLevel).
The $(D LogLevel) of individual loggers can be accessed through the $(D logLevel)
property.

$(D printf)-style formatted logging is supported by the logging functions with
the $(B f) suffix:
-------------
myLogger.infof("Hello %s", "world");
fatalf("errno %d", 1337);
-------------
When combined with conditional logging and/or logging with an
explicit $(D LogLevel), the $(B f) suffix is always placed last.

To implement a custom logger, implement the $(D writeLogMsg) method
of $(D Logger):
-------------
class MyCustomLogger : Logger {
    override void writeLogMsg(ref LoggerPayload payload)
    {
        // log message in my custom way
    }
}

auto logger = new MyCustomLogger();
logger.log("Awesome log message");
-------------


While the idea behind this logging module is to provide a common
interface and easy extensibility, these logger implementations
are provided by the library:

$(LI StdIOLogger, logs data to $(D stdout).)
$(LI FileLogger, logs data to files.)
$(LI MulitLogger, logs data to multiple $(D Logger)s.)
$(LI NullLogger, does nothing.)
$(LI TemplateLogger, base logger to create simple custom loggers.)

In order to disable all logging at compile time, pass $(D DisableLogging) as a
version argument to the compiler.
*/
module std.logger.core;

import std.array;
import std.stdio;
import std.conv;
import std.datetime;
import std.string;
import std.range;
import std.exception;
import std.concurrency;
import std.format;

import std.logger.stdiologger;
import std.logger.multilogger;
import std.logger.filelogger;
import std.logger.nulllogger;

version(DisableTrace)
    immutable TraceLoggingDisabled = true;
else
    immutable TraceLoggingDisabled = false;

version(DisableInfo)
    immutable InfoLoggingDisabled = true;
else
    immutable InfoLoggingDisabled = false;

version(DisableWarning)
    immutable WarningLoggingDisabled = true;
else
    immutable WarningLoggingDisabled = false;

version(DisableCritical)
    immutable CriticalLoggingDisabled = true;
else
    immutable CriticalLoggingDisabled = false;

version(DisableFatal)
    immutable FatalLoggingDisabled = true;
else
    immutable FatalLoggingDisabled = false;

pure bool isLoggingEnabled(LogLevel ll)() @safe nothrow
{
    version(DisableLogging)
    {
        return false;
    }
    else
    {
        static if (ll == LogLevel.trace)
            return !TraceLoggingDisabled;
        else static if (ll == LogLevel.info)
            return !InfoLoggingDisabled;
        else static if (ll == LogLevel.warning)
            return !WarningLoggingDisabled;
        else static if (ll == LogLevel.critical)
            return !CriticalLoggingDisabled;
        else static if (ll == LogLevel.fatal)
            return !FatalLoggingDisabled;
        else
            return true;
    }
}


/** This function logs data.

In order for the data to be processed the $(D LogLevel) of the
$(D defaultLogger) must be greater equal to the global $(D LogLevel).

Params:
args = The data that should be logged.

Returns: The logger used by the logging function as reference.

Examples:
--------------------
log("Hello World", 3.1415);
--------------------
*/
version(DisableLogging)
{
    ref Logger log(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(A) @trusted
    {
        return defaultLogger;
    }
}
else
{
    ref Logger log(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(lazy A args) @trusted
    {
        if (defaultLogger.logLevel >= globalLogLevel
                && globalLogLevel != LogLevel.off
                && defaultLogger.logLevel != LogLevel.off)
        {
            defaultLogger.log!(line, file, funcName,prettyFuncName,
                moduleName)(args);
        }

        return defaultLogger;
    }
}

/** This function logs data depending on a $(D LogLevel) passed
explicitly.

This function takes a $(D LogLevel) as first argument. In order for the
data to be processed the $(D LogLevel) must be greater equal to the
$(D LogLevel) of the used logger, and the global $(D LogLevel).

Params:
logLevel = The $(D LogLevel) used for logging the message.
args = The data that should be logged.

Returns: The logger used by the logging function as reference.

Examples:
--------------------
logl(LogLevel.error, "Hello World");
--------------------
*/
version(DisableLogging)
{
    ref Logger logl(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const LogLevel , A args) @trusted
    {
        return defaultLogger;
    }
}
else
{
    ref Logger logl(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const LogLevel logLevel,
        lazy A args) @trusted
    {
        if (logLevel >= globalLogLevel
                && logLevel >= defaultLogger.logLevel
                && globalLogLevel != LogLevel.off
                && defaultLogger.logLevel != LogLevel.off )
        {
            defaultLogger.logl!(line, file, funcName,prettyFuncName,
                moduleName)(logLevel, args);
        }

        return defaultLogger;
    }
}

/** This function logs data depending on a $(D condition) passed
explicitly.

This function takes a $(D bool) as first argument. In order for the
data to be processed the $(D bool) must be $(D true) and the $(D LogLevel) of
the $(D defaultLogger) must be greater equal to the global $(D LogLevel).

Params:
condition = Only if this $(D bool) is $(D true) will the data be logged.
args = The data that should be logged.

Returns: The logger used by the logging function as reference.

Examples:
--------------------
logc(false, 1337);
--------------------
*/
version(DisableLogging)
{
    ref Logger logc(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const bool , A ) @trusted
    {
        return defaultLogger;
    }
}
else
{
    ref Logger logc(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const bool condition, lazy A args)
        @trusted
    {
        if (condition && defaultLogger.logLevel >= globalLogLevel
                && globalLogLevel != LogLevel.off
                && defaultLogger.logLevel != LogLevel.off )
        {
            defaultLogger.logc!(line, file, funcName,prettyFuncName,
                moduleName)(condition, args);
        }

        return defaultLogger;
    }
}

/** This function logs data depending on a $(D condition) and a $(D LogLevel)
passed explicitly.

This function takes a $(D bool) as first argument and a $(D bool) as second
argument. In order for the
data to be processed the $(D bool) must be $(D true) and the $(D LogLevel) of
the $(D defaultLogger) must be greater equal to the global $(D LogLevel).

Params:
logLevel = The $(D LogLevel) used for logging the message.
condition = Only if this $(D bool) is $(D true) will the data be logged.
args = The data that should be logged.

Returns: The logger used by the logging function as reference.

Examples:
--------------------
loglc(LogLevel.info, someCondition, 13, 37, "Hello World");
--------------------
*/
version(DisableLogging)
{
    ref Logger loglc(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const LogLevel ,
        const bool , A) @trusted
    {
        return defaultLogger;
    }
}
else
{
    ref Logger loglc(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const LogLevel logLevel,
        const bool condition, lazy A args) @trusted
    {
        if (condition && logLevel >= globalLogLevel
                && logLevel >= defaultLogger.logLevel
                && globalLogLevel != LogLevel.off
                && defaultLogger.logLevel != LogLevel.off )
        {
            defaultLogger.loglc!(line, file, funcName,prettyFuncName,
                moduleName)(logLevel, condition, args);
        }

        return defaultLogger;
    }
}

/** This function logs data in a $(D printf)-style manner.

In order for the data to be processed the $(D LogLevel) of the
$(D defaultLogger) must be greater equal to the global $(D LogLevel).

Params:
msg = The $(D string) that is used to format the additional data.
args = The data that should be logged.

Returns: The logger used by the logging function as reference.

Examples:
--------------------
logf("Hello World %f", 3.1415);
--------------------
*/
version(DisableLogging)
{
    ref Logger logf(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(string , A args) @trusted
    {

        return defaultLogger;
    }
}
else
{
    ref Logger logf(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(string msg,
        lazy A args) @trusted
    {
        if (defaultLogger.logLevel >= globalLogLevel
                && globalLogLevel != LogLevel.off
                && defaultLogger.logLevel != LogLevel.off )
        {
            defaultLogger.logf!(line, file, funcName,prettyFuncName,
                moduleName)(msg, args);
        }

        return defaultLogger;
    }
}

/** This function logs data in a $(D printf)-style manner depending on a
$(D condition) and a $(D LogLevel) passed explicitly.

This function takes a $(D LogLevel) as first argument. In order for the
data to be processed the $(D LogLevel) must be greater equal to the
$(D LogLevel) of the used Logger and the global $(D LogLevel).

Params:
logLevel = The $(D LogLevel) used for logging the message.
msg = The $(D string) that is used to format the additional data.
args = The data that should be logged.

Returns: The logger used by the logging function as reference.

Examples:
--------------------
loglf(LogLevel.critical, "%d", 1337);
--------------------
*/
version(DisableLogging)
{
    ref Logger loglf(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const LogLevel logLevel,
        string, A ) @trusted
    {
        return defaultLogger;
    }
}
else
{
    ref Logger loglf(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const LogLevel logLevel,
        string msg, lazy A args) @trusted
    {
        if (logLevel >= globalLogLevel
                && logLevel >= defaultLogger.logLevel
                && globalLogLevel != LogLevel.off
                && defaultLogger.logLevel != LogLevel.off )
        {
            defaultLogger.loglf!(line, file, funcName,prettyFuncName,
                moduleName)(logLevel, msg, args);
        }

        return defaultLogger;
    }
}

/** This function logs data in a $(D printf)-style manner depending on a
$(D condition) passed explicitly

This function takes a $(D bool) as first argument. In order for the
data to be processed the $(D bool) must be $(D true) and the $(D LogLevel) of
the $(D defaultLogger) must be greater equal to the global $(D LogLevel).

Params:
condition = Only if this $(D bool) is $(D true) will the data be logged.
msg = The $(D string) that is used to format the additional data.
args = The data that should be logged.

Returns: The logger used by the logging function as reference.

Examples:
--------------------
logcf(false, "%d", 1337);
--------------------
*/
version(DisableLogging)
{
    ref Logger logcf(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const bool condition,
        string msg, lazy A args) @trusted
    {
        return defaultLogger;
    }
}
else
{
    ref Logger logcf(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const bool condition,
        string msg, lazy A args) @trusted
    {
        if (condition && defaultLogger.logLevel >= globalLogLevel
                && globalLogLevel != LogLevel.off
                && defaultLogger.logLevel != LogLevel.off )
        {
            defaultLogger.logcf!(line, file, funcName,prettyFuncName,
                moduleName)(condition, msg, args);
        }

        return defaultLogger;
    }
}

/** This function logs data in a $(D printf)-style manner depending on a
$(D LogLevel) and a $(D condition) passed explicitly.

This function takes a $(D LogLevel) as first argument and a $(D bool) as
second argument. In order for the data to be processed the $(D bool) must be
$(D true) and the $(D LogLevel) of the $(D defaultLogger) must be greater or
equal to the global $(D LogLevel).

Params:
logLevel = The $(D LogLevel) used for logging the message.
condition = Only if this $(D bool) is $(D true) will the data be logged.
msg = The $(D string) that is used to format the additional data.
args = The data that should be logged.

Returns: The logger used by the logging function as reference.

Examples:
--------------------
loglcf(LogLevel.trace, false, "%d %s", 1337, "is number");
--------------------
*/
version(DisableLogging)
{
    ref Logger loglcf(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const LogLevel, bool, string, A)
        @trusted
    {

        return defaultLogger;
    }
}
else
{
    ref Logger loglcf(int line = __LINE__, string file = __FILE__,
        string funcName = __FUNCTION__,
        string prettyFuncName = __PRETTY_FUNCTION__,
        string moduleName = __MODULE__, A...)(const LogLevel logLevel,
        bool condition, string msg, lazy A args) @trusted
    {
        if (condition && logLevel >= globalLogLevel
                && logLevel >= defaultLogger.logLevel
                &&globalLogLevel != LogLevel.off
                && defaultLogger.logLevel != LogLevel.off )
        {
            defaultLogger.loglcf!(line, file, funcName,prettyFuncName,
                moduleName)(logLevel, condition, msg, args);
        }

        return defaultLogger;
    }
}

///
template DefaultLogFunction(LogLevel ll)
{
    /** This function logs data in a writeln style manner to the
    $(D defaultLogger).

    In order for the resulting log message to be logged the $(D LogLevel) must
    be greater or equal than the $(D LogLevel) of the $(D defaultLogger) and
    must be greater or equal than the global $(D LogLevel).

    Params:
    args = The data that should be logged.

    Returns: The logger used by the logging function as reference.

    Examples:
    --------------------
    trace(1337, "is number");
    info(1337, "is number");
    error(1337, "is number");
    critical(1337, "is number");
    fatal(1337, "is number");
    --------------------
    */
    version(DisableLogging)
    {
        ref Logger DefaultLogFunction(int line = __LINE__,
            string file = __FILE__, string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(A) @trusted
        {
            return defaultLogger;
        }
    }
    else
    {
        ref Logger DefaultLogFunction(int line = __LINE__,
            string file = __FILE__, string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(lazy A args) @trusted
        {
            static if (isLoggingEnabled!ll)
            {
                if (ll >= globalLogLevel
                        && ll >= defaultLogger.logLevel
                        && globalLogLevel != LogLevel.off
                        && defaultLogger.logLevel != LogLevel.off)
                {
                    defaultLogger.MemLogFunctions!(ll).logImpl!(line, file,
                        funcName, prettyFuncName, moduleName)(args);
                }
            }

            return defaultLogger;
        }
    }
}
/// Ditto
alias trace = DefaultLogFunction!(LogLevel.trace);
/// Ditto
alias info = DefaultLogFunction!(LogLevel.info);
/// Ditto
alias warning = DefaultLogFunction!(LogLevel.warning);
/// Ditto
alias error = DefaultLogFunction!(LogLevel.error);
/// Ditto
alias critical = DefaultLogFunction!(LogLevel.critical);
/// Ditto
alias fatal = DefaultLogFunction!(LogLevel.fatal);

///
template DefaultLogFunctionc(LogLevel ll)
{
    /** This function logs data in a writeln style manner to the
    $(D defaultLogger) depending on a condition passed as the first element.

    In order for the resulting log message to be logged the $(D LogLevel) must
    be greater or equal than the $(D LogLevel) of the $(D defaultLogger) and
    must be greater or equal than the global $(D LogLevel). Additionally, the
    condition passed must be true.

    Params:
    condition = The condition
    args = The data that should be logged.

    Returns: The logger used by the logging function as reference.

    Examples:
    --------------------
    tracec(true, 1337, "is number");
    infoc(false, 1337, "is number");
    errorc(4 < 3, 1337, "is number");
    criticalc(4 > 3, 1337, "is number");
    fatalc(someFunctionReturingABool(), 1337, "is number");
    --------------------
    */
    version(DisableLogging)
    {
        ref Logger DefaultLogFunctionc(int line = __LINE__,
            string file = __FILE__, string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const bool, A) @trusted
        {
            return defaultLogger;
        }
    }
    else
    {
        ref Logger DefaultLogFunctionc(int line = __LINE__,
            string file = __FILE__, string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const bool condition,
            lazy A args) @trusted
        {
            static if (isLoggingEnabled!ll)
            {
                if (condition && ll >= globalLogLevel
                        && ll >= defaultLogger.logLevel
                        && globalLogLevel != LogLevel.off
                        && defaultLogger.logLevel != LogLevel.off )
                {
                    defaultLogger.MemLogFunctions!(ll).logImplc!(line, file,
                        funcName, prettyFuncName, moduleName)(condition, args);
                }
            }

            return defaultLogger;
        }
    }
}
/// Ditto
alias tracec = DefaultLogFunctionc!(LogLevel.trace);
/// Ditto
alias infoc = DefaultLogFunctionc!(LogLevel.info);
/// Ditto
alias warningc = DefaultLogFunctionc!(LogLevel.warning);
/// Ditto
alias errorc = DefaultLogFunctionc!(LogLevel.error);
/// Ditto
alias criticalc = DefaultLogFunctionc!(LogLevel.critical);
/// Ditto
alias fatalc = DefaultLogFunctionc!(LogLevel.fatal);

///
template DefaultLogFunctionf(LogLevel ll)
{
    /** This function logs data in a writefln style manner to the
    $(D defaultLogger).

    In order for the resulting log message to be logged the $(D LogLevel) must
    be greater or equal than the $(D LogLevel) of the $(D defaultLogger) and
    must be greater or equal than the global $(D LogLevel).

    Params:
    msg = The format string.
    args = The data that should be logged.

    Returns: The logger used by the logging function as reference.

    Examples:
    --------------------
    tracef("%d %s", 1337, "is number");
    infof("%d %s", 1337, "is number");
    errorf("%d %s", 1337, "is number");
    criticalf("%d %s", 1337, "is number");
    fatalf("%d %s", 1337, "is number");
    --------------------
    */
    version(DisableLogging)
    {
        ref Logger DefaultLogFunctionf(int line = __LINE__,
            string file = __FILE__, string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(string, A)
            @trusted
        {
            return defaultLogger;
        }
    }
    else
    {
        ref Logger DefaultLogFunctionf(int line = __LINE__,
            string file = __FILE__, string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(string msg, lazy A args)
            @trusted
        {
            static if (isLoggingEnabled!ll)
            {
                if (ll >= globalLogLevel
                        && ll >= defaultLogger.logLevel
                        && globalLogLevel != LogLevel.off
                        && defaultLogger.logLevel != LogLevel.off )
                {
                    defaultLogger.MemLogFunctions!(ll).logImplc!(line, file,
                        funcName, prettyFuncName, moduleName)(true, msg, args);
                }
            }

            return defaultLogger;
        }
    }
}

/// Ditto
alias tracef = DefaultLogFunctionf!(LogLevel.trace);
/// Ditto
alias infof = DefaultLogFunctionf!(LogLevel.info);
/// Ditto
alias warningf = DefaultLogFunctionf!(LogLevel.warning);
/// Ditto
alias errorf = DefaultLogFunctionf!(LogLevel.error);
/// Ditto
alias criticalf = DefaultLogFunctionf!(LogLevel.critical);
/// Ditto
alias fatalf = DefaultLogFunctionf!(LogLevel.fatal);

///
template DefaultLogFunctioncf(LogLevel ll)
{
    /** This function logs data in a writefln style manner to the
    $(D defaultLogger) depending on a condition passed as first argument.

    In order for the resulting log message to be logged the $(D LogLevel) must
    be greater or equal than the $(D LogLevel) of the $(D defaultLogger) and
    must be greater or equal than the global $(D LogLevel). Additionally, the
    condition passed must be true.

    Params:
    condition = The condition
    msg = The format string.
    args = The data that should be logged.

    Returns: The logger used by the logging function as reference.

    Examples:
    --------------------
    tracecf(true, "%d %s", 1337, "is number");
    infocf(false, "%d %s", 1337, "is number");
    errorcf(3.14 != PI, "%d %s", 1337, "is number");
    criticalcf(3 < 4, "%d %s", 1337, "is number");
    fatalcf(4 > 3, "%d %s", 1337, "is number");
    --------------------
    */
    version(DisableLogging)
    {
        ref Logger DefaultLogFunctioncf(int line = __LINE__,
            string file = __FILE__, string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const bool,
            string, A) @trusted
        {
            return defaultLogger;
        }
    }
    else
    {
        ref Logger DefaultLogFunctioncf(int line = __LINE__,
            string file = __FILE__, string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const bool condition,
            string msg, lazy A args) @trusted
        {
            static if (isLoggingEnabled!ll)
            {
                if (condition && ll >= defaultLogger.logLevel
                        && defaultLogger.logLevel >= globalLogLevel
                        && globalLogLevel != LogLevel.off
                        && defaultLogger.logLevel != LogLevel.off )
                {
                    defaultLogger.MemLogFunctions!(ll).logImplcf!(line, file,
                        funcName, prettyFuncName, moduleName)(condition, msg,
                        args);
                }
            }

            return defaultLogger;
        }
    }
}

/// Ditto
alias tracecf = DefaultLogFunctioncf!(LogLevel.trace);
/// Ditto
alias infocf = DefaultLogFunctioncf!(LogLevel.info);
/// Ditto
alias warningcf = DefaultLogFunctioncf!(LogLevel.warning);
/// Ditto
alias errorcf = DefaultLogFunctioncf!(LogLevel.error);
/// Ditto
alias criticalcf = DefaultLogFunctioncf!(LogLevel.critical);
/// Ditto
alias fatalcf = DefaultLogFunctioncf!(LogLevel.fatal);

/**
There are eight usable logging level. These level are $(I all), $(I trace),
$(I info), $(I warning), $(I error), $(I critical), $(I fatal), and $(I off).
If a log function with $(D LogLevel.fatal) is called the shutdown handler of
that logger is called.
*/
enum LogLevel : ubyte
{
    all = 1, /** Lowest possible assignable $(D LogLevel). */
    trace = 32, /** $(D LogLevel) for tracing the execution of the program. */
    info = 64, /** This level is used to display information about the
                program. */
    warning = 96, /** warnings about the program should be displayed with this
                   level. */
    error = 128, /** Information about errors should be logged with this
                   level.*/
    critical = 160, /** Messages that inform about critical errors should be
                    logged with this level. */
    fatal = 192,   /** Log messages that describe fatel errors should use this
                  level. */
    off = ubyte.max /** Highest possible $(D LogLevel). */
}

/** This class is the base of every logger. In order to create a new kind of
logger a deriving class needs to implement the $(D writeLogMsg) method.
*/
abstract class Logger
{
    /** LoggerPayload is a aggregation combining all information associated
    with a log message. This aggregation will be passed to the method
    writeLogMsg.
    */
    protected struct LoggerPayload
    {
        /// the filename the log function was called from
        string file;
        /// the line number the log function was called from
        int line;
        /// the name of the function the log function was called from
        string funcName;
        /// the pretty formatted name of the function the log function was
        /// called from
        string prettyFuncName;
        /// the name of the module
        string moduleName;
        /// the $(D LogLevel) associated with the log message
        LogLevel logLevel;
        /// thread id
        Tid threadId;
        /// the time the message was logged.
        SysTime timestamp;
        /// the message
        string msg;
    }

    /** This constructor takes a name of type $(D string), and a $(D LogLevel).

    Every subclass of $(D Logger) has to call this constructor from there
    constructor. It sets the $(D LogLevel), the name of the $(D Logger), and
    creates a fatal handler. The fatal handler will throw an $(D Error) if a
    log call is made with a $(D LogLevel) $(D LogLevel.fatal).
    */
    public this(string newName, LogLevel lv) @safe
    {
        this.logLevel = lv;
        this.name = newName;
        this.fatalHandler = delegate() {
            throw new Error("A Fatal Log Message was logged");
        };
    }

    /** A custom logger needs to implement this method.
    Params:
        payload = All information associated with call to log function.
    */
    public void writeLogMsg(ref LoggerPayload payload);

    /** This method is the entry point into each logger. It compares the given
    $(D LogLevel) with the $(D LogLevel) of the $(D Logger), and the global
    $(LogLevel). If the passed $(D LogLevel) is greater or equal to both the
    message, and all other parameter are passed to the abstract method
    $(D writeLogMsg).
    */
    public void logMessage(string file, int line, string funcName,
            string prettyFuncName, string moduleName, LogLevel logLevel,
            string msg)
        @trusted
    {
        version(DisableLogging)
        {
        }
        else
        {
            auto lp = LoggerPayload(file, line, funcName, prettyFuncName,
                moduleName, logLevel, thisTid, Clock.currTime, msg);
            this.writeLogMsg(lp);
        }
    }

    /** Get the $(D LogLevel) of the logger. */
    public @property final LogLevel logLevel() const pure nothrow @safe
    {
        return this.logLevel_;
    }

    /** Set the $(D LogLevel) of the logger. The $(D LogLevel) can not be set
    to $(D LogLevel.unspecific).*/
    public @property final void logLevel(const LogLevel lv) pure nothrow @safe
    {
        this.logLevel_ = lv;
    }

    /** Get the $(D name) of the logger. */
    public @property final string name() const pure nothrow @safe
    {
        return this.name_;
    }

    /** Set the name of the logger. */
    public @property final void name(string newName) pure nothrow @safe
    {
        this.name_ = newName;
    }

    /** This methods sets the $(D delegate) called in case of a log message
    with $(D LogLevel.fatal).

    By default an $(D Error) will be thrown.
    */
    public final void setFatalHandler(void delegate() dg) @safe {
        this.fatalHandler = dg;
    }

    ///
    template MemLogFunctions(LogLevel ll)
    {
        /** This function logs data in a writeln style manner to the
        used logger.

        In order for the resulting log message to be logged the $(D LogLevel)
        must be greater or equal than the $(D LogLevel) of the used $(D Logger)
        and must be greater or equal than the global $(D LogLevel).

        Params:
        args = The data that should be logged.

        Returns: The logger used by the logging function as reference.

        Examples:
        --------------------
        Logger g;
        g.trace(1337, "is number");
        g.info(1337, "is number");
        g.error(1337, "is number");
        g.critical(1337, "is number");
        g.fatal(1337, "is number");
        --------------------
        */
        version(DisableLogging)
        {
            public ref Logger logImpl(int line = __LINE__,
                string file = __FILE__, string funcName = __FUNCTION__,
                string prettyFuncName = __PRETTY_FUNCTION__,
                string moduleName = __MODULE__, A...)(A args) @trusted
            {
                return this;
            }
        }
        else
        {
            public ref Logger logImpl(int line = __LINE__,
                string file = __FILE__, string funcName = __FUNCTION__,
                string prettyFuncName = __PRETTY_FUNCTION__,
                string moduleName = __MODULE__, A...)(lazy A args) @trusted
            {
                static if (isLoggingEnabled!ll)
                {
                    if (ll >= globalLogLevel
                            && globalLogLevel != LogLevel.off
                            && this.logLevel_ != LogLevel.off)
                    {
                        this.logMessage(file, line, funcName, prettyFuncName,
                            moduleName, ll, text(args));

                        static if (ll == LogLevel.fatal)
                            fatalHandler();
                    }
                }

                return this;
            }
        }

        /** This function logs data in a writeln style manner to the
        used $(D Logger) depending on a condition passed as the first element.

        In order for the resulting log message to be logged the $(D LogLevel)
        must be greater or equal than the $(D LogLevel) of the used $(D Logger)
        and must be greater or equal than the global $(D LogLevel).
        Additionally, the condition passed must be true.

        Params:
        condition = The condition
        args = The data that should be logged.

        Returns: The logger used by the logging function as reference.

        Examples:
        --------------------
        Logger g;
        g.tracec(true, 1337, "is number");
        g.infoc(false, 1337, "is number");
        g.errorc(4 < 3, 1337, "is number");
        g.criticalc(4 > 3, 1337, "is number");
        g.fatalc(someFunctionReturingABool(), 1337, "is number");
        --------------------
        */
        version(DisableLogging)
        {
            public ref Logger logImplc(int line = __LINE__,
                string file = __FILE__, string funcName = __FUNCTION__,
                string prettyFuncName = __PRETTY_FUNCTION__,
                string moduleName = __MODULE__, A...)(const bool, A) @trusted
            {
                return this;
            }
        }
        else
        {
            public ref Logger logImplc(int line = __LINE__,
                string file = __FILE__, string funcName = __FUNCTION__,
                string prettyFuncName = __PRETTY_FUNCTION__,
                string moduleName = __MODULE__, A...)(const bool condition,
                lazy A args) @trusted
            {
                static if (isLoggingEnabled!ll)
                {
                    if (condition && ll >= globalLogLevel
                            && globalLogLevel != LogLevel.off
                            && this.logLevel_ != LogLevel.off)
                    {
                        this.logMessage(file, line, funcName, prettyFuncName,
                            moduleName, ll, text(args));

                        static if (ll == LogLevel.fatal)
                            fatalHandler();
                    }
                }

                return this;
            }
        }

        /** This function logs data in a writefln style manner to the
        used $(D Logger).

        In order for the resulting log message to be logged the $(D LogLevel)
        must be greater or equal than the $(D LogLevel) of the used $(D Logger)
        and must be greater or equal than the global $(D LogLevel).

        Params:
        msg = The format string.
        args = The data that should be logged.

        Returns: The logger used by the logging function as reference.

        Examples:
        --------------------
        Logger g;
        g.tracef("%d %s", 1337, "is number");
        g.infof("%d %s", 1337, "is number");
        g.errorf("%d %s", 1337, "is number");
        g.criticalf("%d %s", 1337, "is number");
        g.fatalf("%d %s", 1337, "is number");
        --------------------
        */
        version(DisableLogging)
        {
            public ref Logger logImplf(int line = __LINE__,
                string file = __FILE__, string funcName = __FUNCTION__,
                string prettyFuncName = __PRETTY_FUNCTION__,
                string moduleName = __MODULE__, A...)(string, A)
                @trusted
            {
                return this;
            }
        }
        else
        {
            public ref Logger logImplf(int line = __LINE__,
                string file = __FILE__, string funcName = __FUNCTION__,
                string prettyFuncName = __PRETTY_FUNCTION__,
                string moduleName = __MODULE__, A...)(string msg, lazy A args)
                @trusted
            {
                static if (isLoggingEnabled!ll)
                {
                    if (ll >= globalLogLevel
                            && globalLogLevel != LogLevel.off
                            && this.logLevel_ != LogLevel.off)
                    {

                        this.logMessage(file, line, funcName, prettyFuncName,
                            moduleName, ll, format(msg, args));

                        static if (ll == LogLevel.fatal)
                            fatalHandler();
                    }
                }

                return this;
            }
        }

        /** This function logs data in a writefln style manner to the
        used $(D Logger) depending on a condition passed as first argument.

        In order for the resulting log message to be logged the $(D LogLevel)
        must be greater or equal than the $(D LogLevel) of the used $(D Logger)
        and must be greater or equal than the global $(D LogLevel).
        Additionally, the condition passed must be true.

        Params:
        condition = The condition
        msg = The format string.
        args = The data that should be logged.

        Returns: The logger used by the logging function as reference.

        Examples:
        --------------------
        Logger g;
        g.tracecf(true, "%d %s", 1337, "is number");
        g.infocf(false, "%d %s", 1337, "is number");
        g.errorcf(3.14 != PI, "%d %s", 1337, "is number");
        g.criticalcf(3 < 4, "%d %s", 1337, "is number");
        g.fatalcf(4 > 3, "%d %s", 1337, "is number");
        --------------------
        */
        version(DisableLogging)
        {
            public ref Logger logImplcf(int line = __LINE__,
                string file = __FILE__, string funcName = __FUNCTION__,
                string prettyFuncName = __PRETTY_FUNCTION__,
                string moduleName = __MODULE__, A...)(const bool, string, A)
                @trusted
            {
                return this;
            }
        }
        else
        {
            public ref Logger logImplcf(int line = __LINE__,
                string file = __FILE__, string funcName = __FUNCTION__,
                string prettyFuncName = __PRETTY_FUNCTION__,
                string moduleName = __MODULE__, A...)(const bool condition,
                string msg, lazy A args) @trusted
            {
                static if (isLoggingEnabled!ll)
                {
                    if (condition && ll >= globalLogLevel
                            && globalLogLevel != LogLevel.off
                            && this.logLevel_ != LogLevel.off)
                    {
                        this.logMessage(file, line, funcName, prettyFuncName,
                            moduleName, ll, format(msg, args));

                        static if (ll == LogLevel.fatal)
                            fatalHandler();
                    }
                }

                return this;
            }
        }
    }

    /// Ditto
    alias trace = MemLogFunctions!(LogLevel.trace).logImpl;
    /// Ditto
    alias info = MemLogFunctions!(LogLevel.info).logImpl;
    /// Ditto
    alias warning = MemLogFunctions!(LogLevel.warning).logImpl;
    /// Ditto
    alias error = MemLogFunctions!(LogLevel.error).logImpl;
    /// Ditto
    alias critical = MemLogFunctions!(LogLevel.critical).logImpl;
    /// Ditto
    alias fatal = MemLogFunctions!(LogLevel.fatal).logImpl;
    /// Ditto
    alias tracec = MemLogFunctions!(LogLevel.trace).logImplc;
    /// Ditto
    alias infoc = MemLogFunctions!(LogLevel.info).logImplc;
    /// Ditto
    alias warningc = MemLogFunctions!(LogLevel.warning).logImplc;
    /// Ditto
    alias errorc = MemLogFunctions!(LogLevel.error).logImplc;
    /// Ditto
    alias criticalc = MemLogFunctions!(LogLevel.critical).logImplc;
    /// Ditto
    alias fatalc = MemLogFunctions!(LogLevel.fatal).logImplc;
    /// Ditto
    alias tracef = MemLogFunctions!(LogLevel.trace).logImplf;
    /// Ditto
    alias infof = MemLogFunctions!(LogLevel.info).logImplf;
    /// Ditto
    alias warningf = MemLogFunctions!(LogLevel.warning).logImplf;
    /// Ditto
    alias errorf = MemLogFunctions!(LogLevel.error).logImplf;
    /// Ditto
    alias criticalf = MemLogFunctions!(LogLevel.critical).logImplf;
    /// Ditto
    alias fatalf = MemLogFunctions!(LogLevel.fatal).logImplf;
    /// Ditto
    alias tracecf = MemLogFunctions!(LogLevel.trace).logImplcf;
    /// Ditto
    alias infocf = MemLogFunctions!(LogLevel.info).logImplcf;
    /// Ditto
    alias warningcf = MemLogFunctions!(LogLevel.warning).logImplcf;
    /// Ditto
    alias errorcf = MemLogFunctions!(LogLevel.error).logImplcf;
    /// Ditto
    alias criticalcf = MemLogFunctions!(LogLevel.critical).logImplcf;
    /// Ditto
    alias fatalcf = MemLogFunctions!(LogLevel.fatal).logImplcf;

    /** This method logs data with the $(D LogLevel) of the used $(D Logger).

    This method takes a $(D bool) as first argument. In order for the
    data to be processed the $(D bool) must be $(D true) and the $(D LogLevel)
    of the Logger must be greater or equal to the global $(D LogLevel).

    Params:
    args = The data that should be logged.

    Returns: The logger used by the logging function as reference.

    Examples:
    --------------------
    auto l = new StdIOLogger();
    l.log(1337);
    --------------------
    */
    version(DisableLogging)
    {
        public ref Logger log(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(A args) @trusted
        {
            return this;
        }
    }
    else
    {
        public ref Logger log(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(lazy A args) @trusted
        {
            if (this.logLevel_ >= globalLogLevel
                    && globalLogLevel != LogLevel.off
                    && this.logLevel_ != LogLevel.off)
            {

                this.logMessage(file, line, funcName, prettyFuncName,
                    moduleName, this.logLevel_, text(args));
            }

            return this;
        }
    }

    /** This method logs data depending on a $(D condition) passed
    explicitly.

    This method takes a $(D bool) as first argument. In order for the
    data to be processed the $(D bool) must be $(D true) and the $(D LogLevel) of
    the Logger must be greater or equal to the global $(D LogLevel).

    Params:
    condition = Only if this $(D bool) is $(D true) will the data be logged.
    args = The data that should be logged.

    Returns: The logger used by the logging function as reference.

    Examples:
    --------------------
    auto l = new StdIOLogger();
    l.logc(false, 1337);
    --------------------
    */
    version(DisableLogging)
    {
        public ref Logger logc(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const bool, A) @trusted
        {
            return this;
        }
    }
    else
    {
        public ref Logger logc(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const bool condition,
            lazy A args) @trusted
        {
            if (condition && this.logLevel_ >= globalLogLevel
                    && globalLogLevel != LogLevel.off
                    && this.logLevel_ != LogLevel.off)
            {
                this.logMessage(file, line, funcName, prettyFuncName,
                    moduleName, this.logLevel_, text(args));
            }

            return this;
        }
    }

    /** This method logs data depending on a $(D LogLevel) passed
    explicitly.

    This method takes a $(D LogLevel) as first argument. In order for the
    data to be processed the $(D LogLevel) must be greater or equal to the
    $(D LogLevel) of the used Logger and the global $(D LogLevel).

    Params:
    logLevel = The $(D LogLevel) used for logging the message.
    args = The data that should be logged.

    Returns: The logger used by the logging function as reference.

    Examples:
    --------------------
    auto l = new StdIOLogger();
    l.logl(LogLevel.error, "Hello World");
    --------------------
    */
    version(DisableLogging)
    {
        public ref Logger logl(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const LogLevel, A)
            @trusted
        {
            return this;
        }
    }
    else
    {
        public ref Logger logl(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const LogLevel logLevel,
            lazy A args) @trusted
        {
            if (logLevel >= this.logLevel
                    && logLevel >= globalLogLevel
                    && globalLogLevel != LogLevel.off
                    && this.logLevel_ != LogLevel.off)
            {
                this.logMessage(file, line, funcName, prettyFuncName,
                    moduleName, logLevel, text(args));
            }

            return this;
        }
    }

    /** This method logs data depending on a $(D condition) and a $(D LogLevel)
    passed explicitly.

    This method takes a $(D bool) as first argument and a $(D bool) as second
    argument. In order for the data to be processed the $(D bool) must be $(D
    true) and the $(D LogLevel) of the Logger must be greater or equal to
    the global $(D LogLevel).

    Params:
    logLevel = The $(D LogLevel) used for logging the message.
    condition = Only if this $(D bool) is $(D true) will the data be logged.
    args = The data that should be logged.

    Returns: The logger used by the logging function as reference.

    Examples:
    --------------------
    auto l = new StdIOLogger();
    l.loglc(LogLevel.info, someCondition, 13, 37, "Hello World");
    --------------------
    */
    version(DisableLogging)
    {
        public ref Logger loglc(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const LogLevel,
            const bool, A) @trusted
        {
            return this;
        }
    }
    else
    {
        public ref Logger loglc(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const LogLevel logLevel,
            const bool condition, lazy A args) @trusted
        {
            if (condition && logLevel >= this.logLevel
                    && logLevel >= globalLogLevel
                    && globalLogLevel != LogLevel.off
                    && this.logLevel_ != LogLevel.off)
            {
                this.logMessage(file, line, funcName, prettyFuncName,
                    moduleName, logLevel, text(args));
            }

            return this;
        }
    }


    /** This method logs data in a $(D printf)-style manner.

    In order for the data to be processed the $(D LogLevel) of the Logger
    must be greater or equal to the global $(D LogLevel).

    Params:
    msg = The $(D string) that is used to format the additional data.
    args = The data that should be logged.

    Returns: The logger used by the logging function as reference.

    Examples:
    --------------------
    auto l = new StdIOLogger();
    l.logf("Hello World %f", 3.1415);
    --------------------
    */
    version(DisableLogging)
    {
        public ref Logger logf(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(string, A)
            @trusted
        {
            return this;
        }
    }
    else
    {
        public ref Logger logf(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(string msg, lazy A args)
            @trusted
        {
            if (this.logLevel_ >= globalLogLevel
                    && globalLogLevel != LogLevel.off
                    && this.logLevel_ != LogLevel.off)
            {

                this.logMessage(file, line, funcName, prettyFuncName,
                    moduleName, this.logLevel_, format(msg, args));
            }

            return this;
        }
    }

    /** This function logs data in a $(D printf)-style manner depending on a
    $(D condition) passed explicitly

    This function takes a $(D bool) as first argument. In order for the
    data to be processed the $(D bool) must be $(D true) and the $(D LogLevel) of
    the Logger must be greater or equal to the global $(D LogLevel).

    Params:
    condition = Only if this $(D bool) is $(D true) will the data be logged.
    msg = The $(D string) that is used to format the additional data.
    args = The data that should be logged.

    Returns: The logger used by the logging function as reference.

    Examples:
    --------------------
    auto l = new StdIOLogger();
    l.logcf(false, "%d", 1337);
    --------------------
    */
    version(DisableLogging)
    {
        public ref Logger logcf(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const bool, string, A)
            @trusted
        {
            return this;
        }
    }
    else
    {
        public ref Logger logcf(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const bool condition,
            string msg, lazy A args) @trusted
        {
            if (condition && this.logLevel_ >= globalLogLevel
                    && globalLogLevel != LogLevel.off
                    && this.logLevel_ != LogLevel.off)
            {
                this.logMessage(file, line, funcName, prettyFuncName,
                    moduleName, this.logLevel_, format(msg, args));
            }

            return this;
        }
    }

    /** This function logs data in a $(D printf)-style manner depending on a
    $(D condition).

    This function takes a $(D LogLevel) as first argument. In order for the
    data to be processed the $(D LogLevel) must be greater or equal to the
    $(D LogLevel) of the used Logger, and the global $(D LogLevel).

    Params:
    logLevel = The $(D LogLevel) used for logging the message.
    msg = The $(D string) that is used to format the additional data.
    args = The data that should be logged.

    Returns: The logger used by the logging function as reference.

    Examples:
    --------------------
    auto l = new StdIOLogger();
    l.loglf(LogLevel.critical, "%d", 1337);
    --------------------
    */
    version(DisableLogging)
    {
        public ref Logger loglf(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const LogLevel, string, A)
            @trusted
        {
            return this;
        }
    }
    else
    {
        public ref Logger loglf(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const LogLevel logLevel,
            string msg, lazy A args) @trusted
        {
            if (logLevel >= this.logLevel
                    && logLevel >= globalLogLevel
                    && globalLogLevel != LogLevel.off
                    && this.logLevel_ != LogLevel.off)
            {
                this.logMessage(file, line, funcName, prettyFuncName,
                    moduleName, logLevel, format(msg, args));
            }

            return this;
        }
    }

    /** This method logs data in a $(D printf)-style manner depending on a $(D
    LogLevel) and a $(D condition) passed explicitly

    This method takes a $(D LogLevel) as first argument. This function takes a
    $(D bool) as second argument. In order for the data to be processed the
    $(D bool) must be $(D true) and the $(D LogLevel) of the Logger must be
    greater or equal to the global $(D LogLevel).

    Params:
    logLevel = The $(D LogLevel) used for logging the message.
    condition = Only if this $(D bool) is $(D true) will the data be logged.
    msg = The $(D string) that is used to format the additional data.
    args = The data that should be logged.

    Returns: The logger used by the logging method as reference.

    Examples:
    --------------------
    auto l = new StdIOLogger();
    l.loglcf(LogLevel.trace, false, "%d %s", 1337, "is number");
    --------------------
    */
    version(DisableLogging)
    {
        public ref Logger loglcf(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const LogLevel,
            const bool, string, A) @trusted
        {
            return true;
        }
    }
    else
    {
        public ref Logger loglcf(int line = __LINE__, string file = __FILE__,
            string funcName = __FUNCTION__,
            string prettyFuncName = __PRETTY_FUNCTION__,
            string moduleName = __MODULE__, A...)(const LogLevel logLevel,
            const bool condition, string msg, lazy A args) @trusted
        {
            if (condition && logLevel >= this.logLevel
                    && logLevel >= globalLogLevel
                    && globalLogLevel != LogLevel.off
                    && this.logLevel_ != LogLevel.off)
            {
                this.logMessage(file, line, funcName, prettyFuncName,
                    moduleName, logLevel, format(msg, args));
            }

            return this;
        }
    }

    private LogLevel logLevel_ = LogLevel.info;
    private string name_;
    private void delegate() fatalHandler;
}

/** This method returns the default $(D Logger).

The Logger is returned as a reference. This means it can be rassigned,
thus changing the $(D defaultLogger).

Example:
-------------
defaultLogger = new StdIOLogger;
-------------
The example sets a new $(D StdIOLogger) as new $(D defaultLogger).
*/
public @property ref Logger defaultLogger() @trusted
{
    static __gshared Logger logger;
    if (logger is null)
    {
        logger = new
            StdIOLogger(globalLogLevel());
    }
    return logger;
}

private ref LogLevel globalLogLevelImpl() @trusted
{
    static __gshared LogLevel ll = LogLevel.all;
    return ll;
}

/** This method returns the global $(D LogLevel). */
public @property LogLevel globalLogLevel() @trusted
{
    return globalLogLevelImpl();
}

/** This method sets the global $(D LogLevel).

Every log message with a $(D LogLevel) lower as the global $(D LogLevel)
will be discarded before it reaches $(D writeLogMessage) method.
*/
public @property void globalLogLevel(LogLevel ll) @trusted
{
    if (defaultLogger !is null)
    {
        defaultLogger.logLevel = ll;
    }
    globalLogLevelImpl() = ll;
}

version(unittest)
{
    import std.array;
    import std.ascii;
    import std.random;

    @trusted string randomString(size_t upto)
    {
        auto app = Appender!string();
        foreach(_ ; 0 .. upto)
            app.put(letters[uniform(0, letters.length)]);
        return app.data;
    }
}

@safe unittest
{
    LogLevel ll = globalLogLevel;
    globalLogLevel = LogLevel.fatal;
    assert(globalLogLevel == LogLevel.fatal);
    globalLogLevel = ll;
}

version(unittest)
{
    class TestLogger : Logger
    {
        int line = -1;
        string file = null;
        string func = null;
        string prettyFunc = null;
        string msg = null;
        LogLevel lvl;

        public this(string n = "", const LogLevel lv = LogLevel.info) @safe
        {
            super(n, lv);
        }

        public override void writeLogMsg(ref LoggerPayload payload) @safe
        {
            this.line = payload.line;
            this.file = payload.file;
            this.func = payload.funcName;
            this.prettyFunc = payload.prettyFuncName;
            this.lvl = payload.logLevel;
            this.msg = payload.msg;
        }
    }

    void testFuncNames(Logger logger) {
        logger.log("I'm here");
    }
}

unittest
{
    auto tl1 = new TestLogger("one");
    testFuncNames(tl1);
    assert(tl1.func == "std.logger.core.testFuncNames", tl1.func);
    assert(tl1.prettyFunc ==
        "void std.logger.core.testFuncNames(Logger logger)", tl1.prettyFunc);
    assert(tl1.msg == "I'm here", tl1.msg);
}

@safe unittest
{
    auto oldunspecificLogger = defaultLogger;
    LogLevel oldLogLevel = globalLogLevel;
    scope(exit)
    {
        defaultLogger = oldunspecificLogger;
        globalLogLevel = oldLogLevel;
    }

    defaultLogger = new TestLogger("testlogger");

    auto ll = [LogLevel.trace, LogLevel.info, LogLevel.warning,
         LogLevel.error, LogLevel.critical, LogLevel.fatal, LogLevel.off];

}

@safe unittest
{
    auto tl1 = new TestLogger("one");
    auto tl2 = new TestLogger("two");

    auto ml = new MultiLogger();
    ml.insertLogger(tl1);
    ml.insertLogger(tl2);
    assertThrown!Exception(ml.insertLogger(tl1));

    string msg = "Hello Logger World";
    ml.log(msg);
    int lineNumber = __LINE__ - 1;
    assert(tl1.msg == msg);
    assert(tl1.line == lineNumber);
    assert(tl2.msg == msg);
    assert(tl2.line == lineNumber);

    ml.removeLogger(tl1.name);
    ml.removeLogger(tl2.name);
    assertThrown!Exception(ml.removeLogger(tl1.name));
}

@safe unittest
{
    bool errorThrown = false;
    auto tl = new TestLogger("one");
    auto dele = delegate() {
        errorThrown = true;
    };
    tl.setFatalHandler(dele);
    tl.fatal();
    assert(errorThrown);
}

@safe unittest
{
    auto l = new TestLogger("_", LogLevel.info);
    string msg = "Hello Logger World";
    l.log(msg);
    int lineNumber = __LINE__ - 1;
    assert(l.msg == msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    l.logc(true, msg);
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    l.logc(false, msg);
    assert(l.msg == msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    msg = "%s Another message";
    l.logf(msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    l.logcf(true, msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    l.logcf(false, msg, "Yet");
    int nLineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    l.loglf(LogLevel.fatal, msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    l.loglcf(LogLevel.fatal, true, msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    l.loglcf(LogLevel.fatal, false, msg, "Yet");
    nLineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    auto oldunspecificLogger = defaultLogger;

    assert(oldunspecificLogger.logLevel == LogLevel.all,
         to!string(oldunspecificLogger.logLevel));

    assert(l.logLevel == LogLevel.info);
    defaultLogger = l;
    assert(globalLogLevel == LogLevel.all,
            to!string(globalLogLevel));

    scope(exit)
    {
        defaultLogger = oldunspecificLogger;
    }

    assert(defaultLogger.logLevel == LogLevel.info);
    assert(globalLogLevel == LogLevel.all);
    assert(log(false) is l);

    msg = "Another message";
    log(msg);
    lineNumber = __LINE__ - 1;
    assert(l.logLevel == LogLevel.info);
    assert(l.line == lineNumber, to!string(l.line));
    assert(l.msg == msg, l.msg);

    logc(true, msg);
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    logc(false, msg);
    assert(l.msg == msg);
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    msg = "%s Another message";
    logf(msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    logcf(true, msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    logcf(false, msg, "Yet");
    nLineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    msg = "%s Another message";
    loglf(LogLevel.fatal, msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    loglcf(LogLevel.fatal, true, msg, "Yet");
    lineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);

    loglcf(LogLevel.fatal, false, msg, "Yet");
    nLineNumber = __LINE__ - 1;
    assert(l.msg == msg.format("Yet"));
    assert(l.line == lineNumber);
    assert(l.logLevel == LogLevel.info);
}

unittest // default logger
{
    import std.file;
    string name = randomString(32);
    string filename = randomString(32) ~ ".tempLogFile";
    FileLogger l = new FileLogger(filename);
    auto oldunspecificLogger = defaultLogger;
    defaultLogger = l;

    scope(exit)
    {
        remove(filename);
        defaultLogger = oldunspecificLogger;
        globalLogLevel = LogLevel.all;
    }

    string notWritten = "this should not be written to file";
    string written = "this should be written to file";

    globalLogLevel = LogLevel.critical;
    assert(l.logLevel == LogLevel.critical);

    logl(LogLevel.warning, notWritten);
    logl(LogLevel.critical, written);

    l.file.flush();
    l.file.close();

    auto file = File(filename, "r");
    assert(!file.eof);

    string readLine = file.readln();
    assert(readLine.indexOf(written) != -1, readLine);
    assert(readLine.indexOf(notWritten) == -1, readLine);
    file.close();
}

unittest
{
    import std.file;
    import core.memory;
    string name = randomString(32);
    string filename = randomString(32) ~ ".tempLogFile";
    auto oldunspecificLogger = defaultLogger;

    scope(exit)
    {
        remove(filename);
        defaultLogger = oldunspecificLogger;
        globalLogLevel = LogLevel.all;
    }

    string notWritten = "this should not be written to file";
    string written = "this should be written to file";

    auto l = new FileLogger(filename);
    defaultLogger = l;
    log.logLevel = LogLevel.fatal;

    loglc(LogLevel.critical, false, notWritten);
    loglc(LogLevel.fatal, true, written);
    l.file.flush();
    destroy(l);

    auto file = File(filename, "r");
    auto readLine = file.readln();
    string nextFile = file.readln();
    assert(!nextFile.empty, nextFile);
    assert(nextFile.indexOf(written) != -1);
    assert(nextFile.indexOf(notWritten) == -1);
    file.close();
}

@safe unittest
{
    auto tl = new TestLogger("tl", LogLevel.all);
    int l = __LINE__;
    tl.info("a");
    assert(tl.line == l+1);
    assert(tl.msg == "a");
    assert(tl.logLevel == LogLevel.all);
    assert(globalLogLevel == LogLevel.all);
    l = __LINE__;
    tl.trace("b");
    assert(tl.msg == "b", tl.msg);
    assert(tl.line == l+1, to!string(tl.line));
}

//pragma(msg, buildLogFunction(true, false, true, LogLevel.unspecific, true));

// testing possible log conditions
@safe unittest
{
    auto oldunspecificLogger = defaultLogger;

    auto mem = new TestLogger("tl");
    defaultLogger = mem;

    scope(exit)
    {
        defaultLogger = oldunspecificLogger;
        globalLogLevel = LogLevel.all;
    }

    int value = 0;
    foreach(gll; [LogLevel.all, LogLevel.trace,
            LogLevel.info, LogLevel.warning, LogLevel.error,
            LogLevel.critical, LogLevel.fatal, LogLevel.off])
    {

        globalLogLevel = gll;

        foreach(ll; [LogLevel.all, LogLevel.trace,
                LogLevel.info, LogLevel.warning, LogLevel.error,
                LogLevel.critical, LogLevel.fatal, LogLevel.off])
        {

            mem.logLevel = ll;

            foreach(cond; [true, false])
            {
                foreach(condValue; [true, false])
                {
                    foreach(memOrG; [true, false])
                    {
                        foreach(prntf; [true, false])
                        {
                            foreach(ll2; [LogLevel.all, LogLevel.trace,
                                    LogLevel.info, LogLevel.warning,
                                    LogLevel.error, LogLevel.critical,
                                    LogLevel.fatal, LogLevel.off])
                            {
                                if (memOrG)
                                {
                                    if (prntf)
                                    {
                                        if (cond)
                                        {
                                            mem.loglcf(ll2, condValue, "%s",
                                                value);
                                        }
                                        else
                                        {
                                            mem.loglf(ll2, "%s", value);
                                        }
                                    }
                                    else
                                    {
                                        if (cond)
                                        {
                                            mem.loglc(ll2, condValue,
                                                to!string(value));
                                        }
                                        else
                                        {
                                            mem.logl(ll2, to!string(value));
                                        }
                                    }
                                }
                                else
                                {
                                    if (prntf)
                                    {
                                        if (cond)
                                        {
                                            loglcf(ll2, condValue, "%s", value);
                                        }
                                        else
                                        {
                                            loglf(ll2, "%s", value);
                                        }
                                    }
                                    else
                                    {
                                        if (cond)
                                        {
                                            loglc(ll2, condValue,
                                                to!string(value));
                                        }
                                        else
                                        {
                                            logl(ll2, to!string(value));
                                        }
                                    }
                                }

                                string valueStr = to!string(value);
                                ++value;

                                bool shouldLog = ((gll != LogLevel.off)
                                    && (ll != LogLevel.off)
                                    && (cond ? condValue : true)
                                    && (ll2 >= gll)
                                    && (ll2 >= ll));

                                /*
                                writefln(
                                    "go(%b) ll2o(%b) c(%b) lg(%b) ll(%b) s(%b)"
                                    , gll != LogLevel.off, ll2 != LogLevel.off,
                                    cond ? condValue : true,
                                    ll2 >= gll, ll2 >= ll, shouldLog);
                                */


                                if (shouldLog)
                                {
                                    assert(mem.msg == valueStr, format(
                                        "gll(%u) ll2(%u) cond(%b)" ~
                                        " condValue(%b)" ~
                                        " memOrG(%b) shouldLog(%b) %s == %s",
                                        gll, ll2, cond, condValue, memOrG,
                                        shouldLog, mem.msg, valueStr
                                    ));
                                }
                                else
                                {
                                    assert(mem.msg != valueStr, format(
                                        "gll(%u) ll2(%u) cond(%b) " ~
                                        "condValue(%b)  memOrG(%b) " ~
                                        "shouldLog(%b) %s != %s", gll,
                                        ll2, cond, condValue, memOrG,shouldLog,
                                        mem.msg, valueStr
                                    ));
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// testing more possible log conditions
@safe unittest
{
    auto mem = new TestLogger("tl");

    scope(exit)
    {
        globalLogLevel = LogLevel.all;
    }

    foreach(gll; [LogLevel.all, LogLevel.trace,
            LogLevel.info, LogLevel.warning, LogLevel.error,
            LogLevel.critical, LogLevel.fatal, LogLevel.off])
    {

        globalLogLevel = gll;

        foreach(ll; [LogLevel.all, LogLevel.trace,
                LogLevel.info, LogLevel.warning, LogLevel.error,
                LogLevel.critical, LogLevel.fatal, LogLevel.off])
        {
            foreach(cond; [true, false])
            {
                mem.logLevel = ll;

                bool gllVSll = LogLevel.trace >= globalLogLevel;
                bool gllOff = globalLogLevel != LogLevel.off;
                bool llOff = mem.logLevel != LogLevel.off;
                bool test = gllVSll && gllOff && llOff && cond;

                mem.line = -1;
                /*writefln("%3d %3d %3d %b g %b go %b lo %b %b %b", LogLevel.trace,
                          mem.logLevel, globalLogLevel, LogLevel.trace >= mem.logLevel,
                        gllVSll, gllOff, llOff, cond, test);
                */

                mem.trace(__LINE__); int line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.tracec(cond, __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.tracef("%d", __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.tracecf(cond, "%d", __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                gllVSll = LogLevel.trace >= globalLogLevel;
                test = gllVSll && gllOff && llOff && cond;

                mem.info(__LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.infoc(cond, __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.infof("%d", __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.infocf(cond, "%d", __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                gllVSll = LogLevel.trace >= globalLogLevel;
                test = gllVSll && gllOff && llOff && cond;

                mem.warning(__LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.warningc(cond, __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.warningf("%d", __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.warningcf(cond, "%d", __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                gllVSll = LogLevel.trace >= globalLogLevel;
                test = gllVSll && gllOff && llOff && cond;

                mem.critical(__LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.criticalc(cond, __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.criticalf("%d", __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;

                mem.criticalcf(cond, "%d", __LINE__); line = __LINE__;
                assert(test ? mem.line == line : true); line = -1;
            }
        }
    }
}

@safe unittest
{
    auto oldunspecificLogger = defaultLogger;

    auto mem = new TestLogger("tl");
    defaultLogger = mem;

    scope(exit)
    {
        defaultLogger = oldunspecificLogger;
        globalLogLevel = LogLevel.all;
    }

    foreach(gll; [LogLevel.all, LogLevel.trace,
            LogLevel.info, LogLevel.warning, LogLevel.error,
            LogLevel.critical, LogLevel.fatal, LogLevel.off])
    {

        globalLogLevel = gll;

        foreach(cond; [true, false])
        {
            bool gllVSll = LogLevel.trace >= globalLogLevel;
            bool gllOff = globalLogLevel != LogLevel.off;
            bool llOff = mem.logLevel != LogLevel.off;
            bool test = gllVSll && gllOff && llOff && cond;

            mem.line = -1;
            /*writefln("%3d %3d %3d %b g %b go %b lo %b %b %b", LogLevel.trace,
                      mem.logLevel, globalLogLevel, LogLevel.trace >= mem.logLevel,
                    gllVSll, gllOff, llOff, cond, test);
            */

            trace(__LINE__); int line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            tracec(cond, __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            tracef("%d", __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            tracecf(cond, "%d", __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            gllVSll = LogLevel.trace >= globalLogLevel;
            test = gllVSll && gllOff && llOff && cond;

            info(__LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            infoc(cond, __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            infof("%d", __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            infocf(cond, "%d", __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            gllVSll = LogLevel.trace >= globalLogLevel;
            test = gllVSll && gllOff && llOff && cond;

            warning(__LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            warningc(cond, __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            warningf("%d", __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            warningcf(cond, "%d", __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            gllVSll = LogLevel.trace >= globalLogLevel;
            test = gllVSll && gllOff && llOff && cond;

            critical(__LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            criticalc(cond, __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            criticalf("%d", __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;

            criticalcf(cond, "%d", __LINE__); line = __LINE__;
            assert(test ? mem.line == line : true); line = -1;
        }
    }
}

// Issue #5
unittest
{
    auto oldunspecificLogger = defaultLogger;

    scope(exit)
    {
        defaultLogger = oldunspecificLogger;
        globalLogLevel = LogLevel.all;
    }

    auto tl = new TestLogger("required name", LogLevel.info);
    defaultLogger = tl;

    trace("trace");
    assert(tl.msg.indexOf("trace") == -1);
    //info("info");
    //assert(tl.msg.indexOf("info") == 0);
}

// Issue #5
unittest
{
    auto oldunspecificLogger = defaultLogger;

    scope(exit)
    {
        defaultLogger = oldunspecificLogger;
        globalLogLevel = LogLevel.all;
    }

    auto logger = new MultiLogger(LogLevel.error);

    auto tl = new TestLogger("required name", LogLevel.info);
    logger.insertLogger(tl);
    defaultLogger = logger;

    trace("trace");
    assert(tl.msg.indexOf("trace") == -1);
    info("info");
    assert(tl.msg.indexOf("info") == -1);
    error("error");
    assert(tl.msg.indexOf("error") == 0);
}

unittest
{
    import std.exception : assertThrown;
    auto tl = new TestLogger();
    assertThrown!Throwable(tl.fatal("fatal"));
}
