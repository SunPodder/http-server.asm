; HTTP Server in x86_64 Assembly
; Author: SunPodder
; License: MIT


SYS_READ equ 0
SYS_WRITE equ 1
SYS_OPEN equ 2
SYS_CLOSE equ 3
SYS_EXIT equ 60
SYS_ACCESS equ 21

SYS_SOCKET equ 41
SYS_SETSOCKOPT equ 54
SYS_BIND equ 49
SYS_SEND equ 44
SYS_RECV equ 45
SYS_LISTEN equ 50
SYS_ACCEPT equ 43
SYS_SENDFILE equ 40

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


section .data
	start_msg 					db "listening on http://127.0.0.1:8000", 10, 0
	socket_err_msg 				db "Error creating socket", 10, 0
	socket_options_err_msg 		db "Error setting socket options", 10, 0
	bind_err_msg				db "Error binding the socket", 10, 0
	listen_err_msg 				db "Error listening for incoming connections", 10, 0
	accept_err_msg				db "Error accepting incoming connections", 10, 0
	read_err_msg				db "Error reading the request", 10, 0
	socket_opt 					dd 1
	index_html 					db "index.html", 0
	request_log					db "GET /", 0
	request_code_200			db " - 200", 10, 0
	request_code_404 			db " - 404", 10, 0

	response_200:
			.status 			db "HTTP/1.1 200 OK", CRLF, CRLF

	response_200_len equ $ - response_200

	response_404:
			.status 			db "HTTP/1.1 404 Not Found", CRLF
			.content_type 		db "Content-Type: text/html", CRLF, CRLF
			.body 				db "<h1>404 Not Found</h1>", CRLF, CRLF

	response_404_len equ $ - response_404
	
	response_500:
			.status 			db "HTTP/1.1 500 Internal Server Error", CRLF
			.content_type 		db "Content-Type: text/html", CRLF, CRLF
			.body 				db "<h1>500 Internal Server Error</h1>", CRLF, CRLF

	response_500_len equ $ - response_500


	server_addr:											; 16 bytes
			.sa_family			dw AF_INET					; 2 bytes
			.port 				dw 	0x401f					; 2 bytes		8000 in little endian
			.ip					dd 0x0100007F				; 4 bytes		127.0.0,1 in little endian
															; the docs state that the address should be in network byte order which is big endian though
															; but it works, and that's all that matters :)

			.zero				dd 0, 0						; 8 bytes padding


section .bss
	request resb 10000
	file_path resb 500
	file_fd resb 8
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
	jle _socket_err					; if rax =< 0, there is an error

	mov [server_fd], rax			; store the socket file descriptor

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
	jne _sock_options_err			; if rax != 0, there is an error

; bind the socket
_bind:
	mov rax, SYS_BIND
	mov rdi, [server_fd]
	mov rsi, server_addr			; address
	mov rdx, 16						; address length
	syscall

	cmp rax, 0
	jne _bind_err					; if rax != 0, there is an error

; listen for incoming connections
_listen:
	mov rax, SYS_LISTEN
	mov rdi, [server_fd]
	mov rsi, 5						; backlog - maximum length of the queue of pending connections
	syscall

	cmp rax, 0
	jne _listen_err					; if rax != 0, there is an error

	print start_msg

; accept incoming connections
__accept_loop:

_accept:
	mov rax, SYS_ACCEPT
	mov rdi, [server_fd]
	mov rsi, 0						; address
	mov rdx, 0						; address length
	syscall

	cmp rax, 0
	jle _accept_err					; if rax =< 0, there is an error

	mov [client_fd], rax			; Store the client socket file descriptor

; read the request
_read:
	mov rax, SYS_READ
	mov rdi, [client_fd]			
	mov rsi, request				; buffer to store the request
	mov rdx, 10000					; buffer size
	syscall

	cmp rax, 0
	jle _read_err					; if rax =< 0, there is an error

; parse the request
_get_requested_file:
	mov rax, request
	add rax, 5						; skip the "GET /" part

	; if file name is empty, serve index.html
	cmp byte [rax], 32
	je _serve_index_html

	mov rdi, rax
.loop:								; keep incrementing rdi until we find a space
	inc rdi
	cmp byte [rdi], 32				; find the first space
	jne .loop

	mov byte [rdi], 0				; null terminate the request
									; rax - pointer to the requested file
	
	mov [file_path], rax			; store the file path
	
_send_file:
	print request_log
	mov rax, [file_path]
	call _print

	; check if the file exists on the disk
	; if it does, send the file
	; if it doesn't, send a 404 response``
	mov rax, SYS_ACCESS
	mov rdi, [file_path]
	mov rsi, 0
	syscall

	cmp rax, 0
	jl _404_not_found			; if rax < 0, the file does not exist

	print request_code_200

	; keep track of send count
	; if error, retry upto 3 times
	mov rbx, 0
.send_header:
	inc rbx
	cmp rbx, 3
	jge _500_error

	mov rax, SYS_SEND
	mov rdi, [client_fd]
	mov rsi, response_200
	mov rdx, response_200_len
	mov r10, 0
	syscall

	cmp rax, response_200_len
	jne .send_header			; if rax != response_200_len, retry

.open_file:
	mov rax, SYS_OPEN
	mov rdi, [file_path]
	mov rsi, 0
	syscall

	cmp rax, 0
	jle _500_error			; if rax =< 0, file was not opened

	mov [file_fd], rax		; store the file descriptor

.send_file:
	mov rax, SYS_SENDFILE
	mov rdi, [client_fd]
	mov rsi, [file_fd]
	mov rdx, 0
	mov r10, 10000
	syscall
	
	cmp rax, 0
	jl _500_error			; if rax < 0, there was an error sending the file

.close_file:
	mov rax, SYS_CLOSE
	mov rdi, [file_fd]
	syscall

	cmp rax, 0
	jl _500_error		; if rax < 0, there was an error sending the file

	jmp _close

_404_not_found:
	print request_code_404
	; send 404 response
	mov rax, SYS_SEND
	mov rdi, [client_fd]
	mov rsi, response_404
	mov rdx, response_404_len
	mov r10, 0
	syscall

	cmp rax, 0
	jl _500_error			; if rax < 0, there was an error sending the response

	jmp _close

; internal server error
_500_error:
	; close the file
	mov rax, SYS_CLOSE
	mov rdi, [file_fd]
	syscall

	; send 500 response
	mov rax, SYS_SEND
	mov rdi, [client_fd]
	mov rsi, response_500
	mov rdx, response_500_len
	mov r10, 0
	syscall

	; close the socket
	jmp _close

; close the socket
_close:
	mov rax, SYS_CLOSE
	mov rdi, [client_fd]
	syscall

jmp __accept_loop


_exit:
	mov rax, SYS_CLOSE
	mov rdi, [server_fd]
	syscall

	exit 0





_serve_index_html:
	mov rax, index_html
	mov [file_path], rax
	jmp _send_file

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

_accept_err:
	print accept_err_msg
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

