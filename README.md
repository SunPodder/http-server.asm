# Simple HTTP Server in x86-64 Linux Assembly

It uses linux system calls so you will need a linux machine to compile and run this.

Install nasm with your system's package manager

```bash
sudo apt install nasm
```

Compile and run with
```bash
make
./main
```

For debugging I found `strace` to be very useful
```bash
strace ./main
```

resources:
- https://filippo.io/linux-syscall-table/
- https://stackoverflow.com/q/74887725
- Linux Man Pages
- System Header files for the values of various constants
- See RFC and MDN docs for HTTP request and response formats

See also:
- https://asmtutor.com/

