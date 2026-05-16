This repository is about "utils.sh", a collection of functions that is to be used with FreeBSD’s /bin/sh.

**NOTE:** This is *not* intended to be used by Linux. It does *not* work with bash.

I have just committed the current state of the file. The documentation is integrated within the file as comments. I plan to write a separate documentation as soon as I have some time. I will also upload a few scripts that make use of utils.sh and that serve as examples.

The following is an excerpt from the head of the file:

    #   This file contains a lot of useful functions for shell scripts.
    #   It is meant to be used with FreeBSD's /bin/sh that is lacking some
    #   features present in zsh, ksh and bash.
    #
    #   HIGHLIGHTS:  Among other things, there are various string functions
    #                (match, contains, isdigit, split, ...), diagnostics
    #                and user interation (Err, Warn, Debug, Confirm, Query),
    #                file handling (getsize, getowner, getmtime), a simple
    #                way to handle command line options (std_getopts) and to
    #                quote arbitrary arguments (quote_args), some functions
    #                that are similar to Python constructs (range, enumerate),
    #                colorized output (red, green, ...), progress report for
    #                long-running jobs, handling of X11 resources and X11 cut
    #                buffers (so a shell script can let the user mark some
    #                text with the mouse), and more.

**IMPORTANT:** This is work in progress. The API may not be stable. In particular, I plan to make small changes to the `array`, `dict` and `Set` fetaures in order to remove a few rough edges.
