## **IMPORTANT:**

These scripts assume that `utils.sh` exists in a directory that is somewhere in your `$PATH`.

If you install things just for yourself as a normal user, the usual way is to create a directory called `bin` inside your home directory, and add it to `$PATH` like this:

    cd $HOME
    mkdir bin
    export PATH=${PATH}:$HOME/bin

You might want to add the above `export` command to the profile of your shell, so it takes effect automatically each time you start a new shell. For zsh that would be `$HOME/.zshenv`, for example. Consult your shell’s documentation for details.

Finally, copy the file `utils.sh` into `$HOME/bin`. It is then available for use by all scripts.
