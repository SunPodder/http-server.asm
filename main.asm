; HTTP Server in x86_64 Assembly
; Author: SunPodder
; License: MIT


SYS_READ equ 0
SYS_WRITE equ 1
SYS_CLOSE equ 3
SYS_EXIT equ 60

SYS_SOCKET equ 41
SYS_SETSOCKOPT equ 54
SYS_BIND equ 49
SYS_SEND equ 44
SYS_RECV equ 45
SYS_LISTEN equ 50
SYS_ACCEPT equ 43

AF_INET equ 2
SOCK_STREAM equ 1

SOL_SOCKET equ 1
SO_REUSEADDR equ 2
SO_REUSEPORT equ 15

STDIN equ 0
STDOUT equ 1

%macro exit 1
	mov rax, SYS_EXIT
	mov rdi, %1
	syscall
%endmacro

%macro print 1
	mov rax, %1
	call _print
%endmacro

%define CRLF 13, 10
%define PORT 8000


section .data
	socket_err_msg db "Error creating socket", 10, 0
	socket_options_err_msg db "Error setting socket options", 10, 0
	bind_err_msg db "Error binding the socket", 10, 0
	listen_err_msg db "Error listening for incoming connections", 10, 0
	read_err_msg db "Error reading the request", 10, 0
	socket_opt dd 1

	server_addr:							; 16 bytes
		sa_family		dw AF_INET			; 2 bytes
		port 	dw 	0x401f					; 2 bytes		8000 in little endian
		ip		dd 0x0100007F				; 4 bytes		127.0.0,1 in little endian
											;				the docs state that the address should be in network byte order which is big endian though
											; 				but it works, and that's all that matters :)

		zero			dd 0, 0				; 8 bytes		padding


section .bss
	request resb 10000
	server_fd resb 8
	client_fd resb 8

section .text
	global _start

_start:

; workflow of a server
; 1. create a socket
; 2. set some options
; 3. bind the socket
; 4. listen for incoming connections
; 5. accept incoming connections
; 6. read the request
; 7. parse the request
; 8. get the requested file
; 9. send the file
; 10. close the socket
; 11. go back to step 5


; create a socket
_socket:
	mov rax, SYS_SOCKET
	mov rdi, AF_INET				; domain
	mov rsi, SOCK_STREAM			; type
	mov rdx, 0						; protocol
	syscall

	cmp rax, 0
	jle _socket_err					; If rax =< 0, there is an error

	mov [server_fd], rax			; Store the socket file descriptor

; set socket options
_setsockopt:
	mov rax, SYS_SETSOCKOPT
	mov rdi, [server_fd]					; socket file descriptor
	mov rsi, SOL_SOCKET
	mov rdx, SO_REUSEADDR | SO_REUSEPORT	; option name
											; SO_REUSEADDR - allows other sockets to bind to an address even if it is already in use
											; SO_REUSEPORT - allows multiple sockets to bind to the same address and port
	mov r10, socket_opt						; option value
	mov r8, 4
	syscall


	cmp rax, 0
	jne _sock_options_err			; If rax != 0, there is an error

; bind the socket
_bind:
	mov rax, SYS_BIND
	mov rdi, [server_fd]
	mov rsi, server_addr			; address
	mov rdx, 16						; address length
	syscall

	cmp rax, 0
	jne _bind_err					; If rax != 0, there is an error

; listen for incoming connections
_listen:
	mov rax, SYS_LISTEN
	mov rdi, [server_fd]
	mov rsi, 5						; backlog - maximum length of the queue of pending connections
	syscall

	cmp rax, 0
	jne _listen_err					; If rax != 0, there is an error


; accept incoming connections
__accept_loop:

_accept:
	mov rax, SYS_ACCEPT
	mov rdi, [server_fd]
	mov rsi, 0						; address
	mov rdx, 0						; address length
	syscall

	cmp rax, 0
	jle _socket_err					; If rax =< 0, there is an error

	mov [client_fd], rax			; Store the client socket file descriptor

; read the request
_read:
	mov rax, SYS_READ
	mov rdi, [client_fd]			
	mov rsi, request				; buffer to store the request
	mov rdx, 10000					; buffer size
	syscall

	cmp rax, 0
	jle _socket_err					; If rax =< 0, there is an error

_print_request:
	mov rax, request
	call _print

; close the socket
_close:
	mov rax, SYS_CLOSE
	mov rdi, [server_fd]
	syscall

jmp __accept_loop


_exit:
	exit 0







;
; Error handling
;
_socket_err:
	print socket_err_msg
	exit 1

_sock_options_err:
	print socket_options_err_msg
	exit 1

_bind_err:
	print bind_err_msg
	exit 1

_listen_err:
	print bind_err_msg
	exit 1

_read_err:
	print read_err_msg
	exit 1


; @param rax - pointer to string
; @return rax - length of string
_strlen:
	xor rbx, rbx	; rbx - string length
.strLenLoop:
	inc rbx
	inc rax

	mov cl, [rax]	; cl - current char
	cmp cl, 0
	jne .strLenLoop

	mov rax, rbx	; return length
	ret


; @param rax - pointer to string
; @return rax - length of string
_print:
	push rax		; save string pointer
	call _strlen	; rax - length of string
	push rax

	mov rax, 1		; write syscall
	mov rdi, STDOUT
	pop rdx			; length
	pop rsi			; string pointer
	syscall
	mov rax, rbx	; return length
	ret

