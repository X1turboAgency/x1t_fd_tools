;-----------------------------------;
; 実行前の確認。y/Yだけで続行、n/Nで中止する。FDへのアクセスは行わない。
; 書き戻しの2回目は入力D88の検査後、物理FDDに触る直前に行う。
; 操作対象を表示し、読取り・情報表示・書き戻しの開始確認を行う。
;-----------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT
;-----------------------------------;

IF TOOL_RESTORE
;-----------------------------------;
; 入力D88と書込み対象を表示し、最初の確認を行う。
; 入力条件: d88_final_fcbとFD・メディア・範囲の設定。
; 戻り値: Cy=0: y/Y。Cy=1: n/Nで中止。
;-----------------------------------;
confirm_restore:
	ld		de, confirm_msg_write
	call	print_system

	call	confirm_print_filename

	ld		de, confirm_msg_from_file
	call	print_system

	call	confirm_print_fd
	call	confirm_print_range

	ld		de, confirm_msg_restore
	call	print_system

	ld		de, confirm_msg_overwrite
	call	print_system

	jp		confirm_ask

;-----------------------------------;
; D88の事前検査後、物理FDの書込み開始を再確認する。
; 入力条件: FDとメディアの設定。事前検査は完了していること。
; 戻り値: Cy=0: y/Y。Cy=1: n/Nで中止。
;-----------------------------------;
confirm_restore_start:
	call	confirm_print_fd
	ld		de, confirm_msg_start_write

	call	print_system
	jp		confirm_read_answer
;
ELSE
;-----------------------------------;
; FDからD88へ保存する対象と出力名を表示して確認する。
; 入力条件: d88_final_fcbとFD・メディア・範囲の設定。
; 戻り値: Cy=0: y/Y。Cy=1: n/Nで中止。
;-----------------------------------;
confirm_dump:
	ld		de, confirm_msg_read
	call	print_system
	call	confirm_print_fd
	call	confirm_print_range

	ld		de, confirm_msg_read_to_file
	call	print_system
	call	confirm_print_filename

	ld		de, confirm_msg_create
	call	print_system
	jp		confirm_ask

;-----------------------------------;
; FDからトラック情報だけを取得する操作を確認する。
; 入力条件: FD・メディア・範囲の設定。
; 戻り値: Cy=0: y/Y。Cy=1: n/Nで中止。
;-----------------------------------;
confirm_info:
	ld		de, confirm_msg_read
	call	print_system
	call	confirm_print_fd
	call	confirm_print_range

	ld		de, confirm_msg_info
	call	print_system
	jp		confirm_ask

ENDIF
;-----------------------------------;
; 物理ドライブ番号とメディアをfd番号/メディア形式で表示する。
; 入力条件: drive_no、media_type。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
confirm_print_fd:
	ld		de, confirm_msg_fd
	call	print_system

	ld		a, (drive_no)
	call	print_decimal

	ld		de, confirm_msg_slash
	call	print_system

	ld		a, (media_type)
	ld		de, confirm_msg_2d
	or		a
	jr		z, confirm_media
;
	ld		de, confirm_msg_2dd
	cp		DISK_TYPE_2DD
	jr		z, confirm_media
;
	ld		de, confirm_msg_2hd
confirm_media:
	jp		print_system

;-----------------------------------;
; 選択した開始・終了トラック番号を表示する。
; 入力条件: start_track_no、end_track_no。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
confirm_print_range:
	ld		de, confirm_msg_track
	call	print_system

	ld		a, (start_track_no)
	call	print_decimal

	ld		de, str_dash
	call	print_system

	ld		a, (end_track_no)
	jp		print_decimal

;-----------------------------------;
; FCBの空白を省いたドライブ付きファイル名を表示する。
; 入力条件: d88_final_fcb。
; 戻り値: 表示のみ。$も通常文字として表示する。
;-----------------------------------;
confirm_print_filename:
	ld		a, (d88_final_fcb)
	or		a
	jr		nz, confirm_filename_drive
;
	ld		c, CMD_GET_CURRENT_DRIVE
	call	SYSTEM
	inc		a

confirm_filename_drive:
	add		a, 'A'-1
	ld		e, a
	ld		c, CMD_CHAR_OUT
	call	SYSTEM

	ld		de, confirm_msg_colon
	call	print_system

	ld		hl, d88_final_fcb+1
	ld		b, 8
	call	confirm_filename_part

	push	hl
	ld		de, confirm_msg_dot
	call	print_system
	pop		hl

	ld		b, 3

;-----------------------------------;
; ファイル名の一部分を空白を省いて表示する。
; 入力条件: HLreg: 名前または拡張子。Breg: 検査する文字数（1以上）。
; 戻り値: HLreg: 指定文字数だけ進んだ位置。Breg=0。
;-----------------------------------;
confirm_filename_part:
	ld		a, (hl)
	cp		' '
	jr		z, confirm_filename_next
;
	push	bc
	push	hl
	ld		e, a
	ld		c, CMD_CHAR_OUT
	call	SYSTEM
	pop		hl
	pop		bc

confirm_filename_next:
	inc		hl
	djnz	confirm_filename_part
;
	ret
;
;-----------------------------------;
; 続行確認を表示して回答入力へ進む。
; 入力条件: なし。
; 戻り値: Cy=0: y/Y。Cy=1: n/N。
;-----------------------------------;
confirm_ask:
	ld		de, confirm_msg_continue
	call	print_system

;-----------------------------------;
; 改行を読み飛ばしてy/nの回答を待つ。
; 入力条件: なし。
; 戻り値: Cy=0: y/Y。Cy=1: n/N。それ以外は再入力を求める。
;-----------------------------------;
confirm_read_answer:
	ld		c, CMD_CHAR_IN
	call	SYSTEM
	cp		13
	jr		z, confirm_read_answer
;
	cp		10
	jr		z, confirm_read_answer
;
	and		0dfh
	cp		'Y'
	jr		z, confirm_yes
;
	cp		'N'
	jr		z, confirm_no
;
	call	print_crlf
	ld		de, confirm_msg_answer
	call	print_system
	jr		confirm_read_answer
;
confirm_no:
	call	print_crlf
	ld		de, confirm_msg_cancel
	call	print_system
	scf
	ret
;
confirm_yes:
	call	print_crlf
	xor		a
	ret
;
confirm_msg_fd: db "fd",END_CODE
confirm_msg_slash: db "/",END_CODE
confirm_msg_colon: db ":",END_CODE
confirm_msg_dot: db ".",END_CODE
confirm_msg_2d: db "2d",END_CODE
confirm_msg_2dd: db "2dd",END_CODE
confirm_msg_2hd: db "2hd",END_CODE
confirm_msg_track: db " track ",END_CODE
confirm_msg_continue: db "Continue? (y/n) ",END_CODE
confirm_msg_answer: db "Please enter y or n. (y/n) ",END_CODE
confirm_msg_cancel: db "Cancelled.",13,10,END_CODE
IF TOOL_RESTORE
confirm_msg_write: db "Write ",END_CODE
confirm_msg_from_file: db " to ",END_CODE
confirm_msg_restore: db ".",13,10,END_CODE
confirm_msg_overwrite: db "WARNING: Recorded tracks in the selected range will be overwritten.",13,10,END_CODE
confirm_msg_start_write: db " - start writing? (y/n) ",END_CODE
ELSE
confirm_msg_read: db "Read ",END_CODE
confirm_msg_read_to_file: db " to ",END_CODE
confirm_msg_create: db ".",13,10,END_CODE
confirm_msg_info: db " and show track information.",13,10,END_CODE
ENDIF

; ---
END
