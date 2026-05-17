This is a list of to-do items, in no particular order.

* More / better documentation.
    * Currently, all documentation is contained as comments wihtin `utils.sh` itself. Consider creating a separate doc file.
    * The documentation of some features is somewhat terse, in particular `array`, `dict` and `Set`. This needs to be improved.

* I'm not happy with the syntax of the `assert` function. In particular, the double dash `--` is used as a separator, but this character sequence may occur as an argument (after variable expansion) on the left side, causing breakage.

  Typical example: A script tries to validate that the first argument is an existing file:

      assert isfile "$INPUT" -- Err "File not found: $INPUT"
  If `$INPUT` happens to be given as `--`, then the above assert command breaks, causing an error message from the shell:

      sh: --: not found
  Currently, there is a workaround by checking for a list of functions (`match`, `eq`, `isdigit`, etc.), and of course `isfile` could be added to that list. But I regard this as a dirty hack. Even if I add all known functions supported by utils.sh, it would still break with external commands or user-supplied functions.

  I'm currently unsure how to fix this. Maybe a good start would be to use a character sequence as a separator that is less likely to occur on a command line. It should be reasonably short, and it should not require quoting.

  I'm considering to use a double slash `//`. I like this because it looks a bit like the “or” operator `||`. It is also not very likely to occur as an argument on a shell command line.

  Another way to mitigate the problem is to regard only the **last** occurence of the separator string, if it occurs multiple times. This would fix the above example, but it would make the command parsing inside the `assert` function even more complex. It would also mean that the separator string must not occur as an argument in the failure command. Also, it won’t help if there is no failure command at all (causing the default action to take place, i.e. print the usage message).
