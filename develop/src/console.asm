;-----------------------------------;
; 共通の表示。メッセージは英語（ASCII）。ソースはCP932で保持する。
; メッセージ、数値、ファイル名とディスク操作の進行状況を表示する。
;-----------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT

;-----------------------------------;
; LSX-Dodgersの文字列出力を呼び出す。
; 入力条件: DEreg: $終端文字列の先頭。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
print_system:
	ld		c, CMD_STR_OUT
	jp		SYSTEM
;
;-----------------------------------;
; 改行コードCR・LFを表示する。
; 入力条件: なし。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
print_crlf:
	ld		de, str_crlf
	jp		print_system

;-----------------------------------;
; 空白を1文字表示する。
; 入力条件: なし。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
print_space:
	ld		de, str_space
	jp		print_system

;
;-----------------------------------;
; 実行コマンドとモードに対応するタイトルを表示する。
; 入力条件: TOOL_RESTORE、およびFD2IMGではcli_info。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
print_title_str:
IF TOOL_RESTORE
ELSE
	ld		a, (cli_info)
	or		a
	jr		z, print_dump_title
;
	ld		de, str_title_info
	jp		print_system
;
print_dump_title:
ENDIF
	ld		de, str_title
	jp		print_system
;
;-----------------------------------;
; 正常完了のメッセージを表示する。
; 入力条件: なし。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
print_done:
	ld		de, str_done
	jp		print_system
;
;-----------------------------------;
; FCBからドライブ付きのD88ファイル名を表示する。
; 入力条件: d88_final_fcb。ドライブ省略時はカレントドライブを取得する。
; 戻り値: 表示のみ。ファイルのオープンは行わない。
;-----------------------------------;
print_read_filename:
	ld		a, (d88_final_fcb)
	or		a
	jr		nz, print_output_drive
;
	ld		c, CMD_GET_CURRENT_DRIVE
	call	SYSTEM
	inc		a
print_output_drive:
	add		a, 'A'-1
	ld		(str_d88_drive), a
	ld		hl, d88_final_fcb+1
	ld		de, str_filename
	ld		bc, 8
	ldir
	inc		de
	ld		bc, 3
	ldir
	ld		de, str_d88_filename
	call	print_system
	ld		hl, str_filename
	ld		b, 12
print_filename_char:
	push	bc
	push	hl
	ld		e, (hl)
	ld		c, CMD_CHAR_OUT
	call	SYSTEM
	pop		hl
	pop		bc
	inc		hl
	djnz	print_filename_char
;
	jp		print_crlf
;
;-----------------------------------;
; FD番号・メディアと論理トラック範囲を表示する。
; 入力条件: drive_no、media_type、start_track_no、end_track_no。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
print_settings:
	ld		a, (drive_no)
	add		a, '0'
	ld		(str_fd_number), a
	ld		de, str_settings
	call	print_system
	ld		a, (media_type)
	ld		de, str_media_2d
	or		a
	jr		z, print_media
;
	ld		de, str_media_2dd
	cp		DISK_TYPE_2DD
	jr		z, print_media
;
	ld		de, str_media_2hd
print_media:
	call	print_system
	ld		de, str_range
	call	print_system
	ld		a, (start_track_no)
	call	print_decimal
	ld		de, str_dash
	call	print_system
	ld		a, (end_track_no)
	call	print_decimal
	jp		print_crlf
;
;-----------------------------------;
; 8ビット符号なし整数を先頭ゼロなしの10進数で表示する。
; 入力条件: Areg: 0～255。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
print_decimal:
	ld		hl, number_buffer
	call	dec3_asc
	ld		(hl), END_CODE
	ld		de, number_buffer
	jp		print_system
;
; FDD番号・メディアを設定し、現在の論理トラックを表示する。
;-----------------------------------;
; FD番号とメディアを設定し、対象トラックを表示する。
; 入力条件: DEreg: $終端メッセージ。drive_no、media_type、start_track_no。
; 戻り値: Areg: 現在の論理トラック番号。
;-----------------------------------;
setup_drive_param:
	push	de
	call	select_drive_param
	pop		de
	call	print_system
	ld		a, (start_track_no)
	jr		text_puts_track
;
; 表示せずにFDD番号とメディアだけを設定する。
;-----------------------------------;
; 表示せずに物理ドライブとメディアモードを設定する。
; 入力条件: drive_no、media_type。
; 戻り値: 設定のみ。フラグは判定に使用しない。
;-----------------------------------;
select_drive_param:
	ld		a, (drive_no)
	call	set_cur_drive
	ld		a, (media_type)
	jp		set_fdd_mode
;
;-----------------------------------;
; トラック番号を10進数で表示して改行する。
; 入力条件: Areg: トラック番号。
; 戻り値: Aregとフラグを保存する。
;-----------------------------------;
text_puts_track:
	push	af
	call	print_decimal
	call	print_crlf
	pop		af
	ret
;
;-----------------------------------;
; FDCの状態値を2桁の16進数で表示する。
; 入力条件: Areg: 状態値。
; 戻り値: AFreg・HLreg・DEregを保存する。
;-----------------------------------;
print_disk_stat:
	push	af
	push	hl
	push	de
	ld		hl, disk_stat_str_hex
	call	hex2_asc
	ld		de, disk_stat_str
	jr		print_preserved
;
;-----------------------------------;
; 正常セクタの番号を#に続けて16進数で表示する。
; 入力条件: Areg: セクタ番号。
; 戻り値: AFreg・HLreg・DEregを保存する。
;-----------------------------------;
print_sector:
	push	af
	push	hl
	push	de
	ld		hl, sector_str_hex
	call	hex2_asc
	ld		de, sector_str
	jr		print_preserved
;
;-----------------------------------;
; 異常セクタの番号をxに続けて16進数で表示する。
; 入力条件: Areg: セクタ番号。
; 戻り値: AFreg・HLreg・DEregを保存する。
;-----------------------------------;
print_sector_NG:
	push	af
	push	hl
	push	de
	ld		hl, sector_str_NG_hex
	call	hex2_asc
	ld		de, sector_str_NG

print_preserved:
	call	print_system
	pop		de
	pop		hl
	pop		af
	ret
;
;-----------------------------------;
; 8ビット値を大文字2桁の16進文字列へ変換する。
; 入力条件: Areg: 変換値。HLreg: 2バイト以上の書込み先。
; 戻り値: HLreg: 書込み先の2バイト後。終端文字は付けない。
;-----------------------------------;
hex2_asc:
	push	af
	rrca
	rrca
	rrca
	rrca
	call	hex1_asc
	pop		af

;HEX NIBBLE to ASCII convert
;hl = buffer pointer(1byte)
;a[0..3] = value
;-----------------------------------;
; 下位4ビットを大文字1桁の16進文字へ変換する。
; 入力条件: Areg: 下位4ビットを使用。HLreg: 書込み先。
; 戻り値: HLreg: 次の書込み位置。Areg: 変換したASCII文字。
;-----------------------------------;
hex1_asc:
	and		0fh

	add		a, 30h
	cp		'9'+1
	jr		c, hex1_as_1
;
	add		a, 07h		; 'A'-'9'-1
hex1_as_1:
	ld		(hl), a
	inc		hl
	ret

;-----------------------------------;
; 8ビット値を先頭ゼロなしの10進文字列へ変換する。
; 入力条件: Areg: 0～255。HLreg: 3バイト以上の書込み先。
; 戻り値: HLreg: 変換文字列の直後。BCreg・DEregを保存し、終端は付けない。
;-----------------------------------;
dec3_asc:
	push	de
	push	bc

	ld		c, 100
	call	count_sub
	ld		d, b
	ld		c, 10
	call	count_sub
	ld		e, b

	; この時点でD 100の位 E 10の位 A 1の位が入っている。
	ld		b, 0
	push	af
	ld		a, d
	call	dec_store
	ld		a, e
	call	dec_store
	pop		af
	inc		b ; '0'以外出現フラグを立てる。
	call	dec_store

	pop		bc
	pop		de
	ret

; 10進数の桁をストアする。
; Areg: 0～9
; Breg: 0:'0'以外がまだ出現していない 1:'0'がすでに出現した。
;-----------------------------------;
; 先頭ゼロを省略しながら10進数の1桁を書き込む。
; 入力条件: Areg: 0～9。Breg: 出力開始状態。HLreg: 書込み先。
; 戻り値: 出力時にHLregを進め、Bregを更新する。
;-----------------------------------;
dec_store:
	; 値が0かどうか
	or		a
	jr		nz, ds_1

	; 値が0で、'0'以外が出現したフラグをチェック。
	inc		b
	dec		b
	ret		z
;
ds_1:
	add		a, '0'
	ld		(hl), a
	inc		hl

	inc		b ; '0'以外が出現したフラグをセットする。
	ret

; AregからCregが何回引けるか数える。
; 戻り値:
;	Breg: 引いた回数
;	Areg: 余り
;-----------------------------------;
; 指定値を繰り返し減算し、商と余りを求める。
; 入力条件: Areg: 被除数。Creg: 0以外の除数。
; 戻り値: Breg: 商。Areg: 余り。
;-----------------------------------;
count_sub:
	ld		b, 0
cs_2:
	cp		c
	ret		c
;
	inc		b
	sub		c
	jr		cs_2


str_title:
IF TOOL_RESTORE
	db		"# X1turbo IMG2FD : D88 -> FD (v1.0)", 13, 10, END_CODE
ELSE
	db		"# X1turbo FD2IMG (D88 image mode) (v1.0)", 13, 10, END_CODE
ENDIF
IF TOOL_RESTORE
ELSE
str_title_info: db "** X1turbo FD2IMG (disk info mode) (v1.0) **",13,10,END_CODE
ENDIF
str_crlf: db 13,10,END_CODE
str_space: db " ", END_CODE
str_platform_unsupported: db "Error: Unsupported platform. X1turbo is required.",13,10,END_CODE
str_done: db "Done.",13,10,END_CODE
str_d88_filename:
IF TOOL_RESTORE
	db		"Input D88: "
ELSE
	db		"Output D88: "
ENDIF
str_d88_drive: db "?:",END_CODE
str_filename: ds 8,' '
	db		'.'
	ds		3, ' '
	db		13, 10, END_CODE
str_settings:
IF TOOL_RESTORE
	db		"Target FD: "
ELSE
	db		"Source FD: "
ENDIF
str_fd_number: db '0',"  Media: ",END_CODE
str_media_2d: db "2D",END_CODE
str_media_2dd: db "2DD",END_CODE
str_media_2hd: db "2HD",END_CODE
str_range: db "  Logical track: ",END_CODE
str_dash: db '-', END_CODE
cmd03_msg: db "Read track: ",END_CODE
cmd_write_msg: db "Write track: ",END_CODE
disk_stat_str: db 13,10,"FDC status: "
disk_stat_str_hex: ds 2
	db		13, 10, END_CODE
sector_str: db '#'
sector_str_hex: ds 2
	db		' ', END_CODE
sector_str_NG: db 'x'
sector_str_NG_hex: ds 2
	db		' ', END_CODE
number_buffer: ds 4,0


END
