;-----------------------------------;
; D88共通定義・ファイル名・ヘッダ領域
; 両コマンドで共用するD88定数・FCB・ヘッダとファイル名処理を提供する。
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT
;-----------------------------------;

D88_HEADER_SIZE        equ 02b0h
D88_TRACK_COUNT        equ 164
D88_FCB_SIZE           equ 37


;-----------------------------------;
; FCB1からD88のファイル名を用意し、禁止文字を検査する。
; 入力条件: FCB1: ドライブと8.3形式の名前。
; 戻り値: Cy=0: d88_final_fcbを設定。Cy=1: 不正な名前。
;-----------------------------------;
d88_prepare_name:
	ld		hl, d88_default_name ; デフォルト出力名
	ld		de, d88_final_fcb
	ld		bc, 12
	ldir

	; FCB drive: 0=current, 1=A ... 26=Z. (他のドライブは選択しない)
	ld		a, (FCB1)
	cp		27
	jp		nc, d88_fail_name
;
	ld		(d88_final_fcb), a

	ld		a, (FCB1+1)
	or		a
	jr		z, d88_name_ready
;
	cp		' '
	jr		z, d88_name_ready
;
	ld		hl, FCB1+1
	ld		de, d88_final_fcb+1
	ld		bc, 11
	ldir
	ld		a, (d88_final_fcb+9)
	cp		' '
	jr		nz, d88_name_ready
;
	ld		hl, d88_default_name+9
	ld		de, d88_final_fcb+9
	ld		bc, 3
	ldir

; 出力ファイル名の整合性チェック
d88_name_ready:
	ld		hl, d88_final_fcb+1
	ld		b, 11

d88_pr_na_1:
	ld		a, (hl)
	cp		'*'
	jp		z, d88_fail_name
;
	cp		'?'
	jp		z, d88_fail_name
;
	cp		'/'
	jp		z, d88_fail_name
;
	cp		05ch ; バックスラッシュ: ファイル名指定では無効
	jp		z, d88_fail_name
;
	inc		hl
	djnz	d88_pr_na_1
;
	; '$$' をチェック
	ld		hl, (d88_final_fcb+9)
	ld		de, 02424h
	or		a
	sbc		hl, de
	jr		nz, d88_name_valid
;
	; 更に、'$'をチェック
	ld		a, (d88_final_fcb+11)
	cp		'$'
	jp		z, d88_fail_name
;
d88_name_valid:
	; D88ファイル名確定
	ld		hl, d88_final_fcb+12
	call	d88_clear_fcb_work

	xor		a
	ret

;-----------------------------------;
; FCBの名前以降の作業フィールドをゼロにする。
; 入力条件: HLreg: FCB先頭+12。
; 戻り値: HLreg: FCB領域の直後。Areg=0、Breg=0。
;-----------------------------------;
d88_clear_fcb_work:
	ld		b, D88_FCB_SIZE-12
	xor		a

d88_cl_fc_wo_1:
	ld		(hl), a
	inc		hl
	djnz	d88_cl_fc_wo_1
;
	ret

d88_fail_name:
	ld		hl, d88_msg_name
	jr		d88_fail
;
d88_fail_exists:
	ld		hl, d88_msg_exists
	jr		d88_fail
;
d88_fail_data:
	ld		hl, d88_msg_data
	jr		d88_fail
;
d88_fail_io:
	ld		hl, d88_msg_io
d88_fail:
	ld		(d88_error_message), hl
	scf
	ret

;-----------------------------------;
; D88処理で設定されたエラーメッセージを表示する。
; 入力条件: d88_error_message: $終端文字列のアドレス。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
d88_print_error:
	ld		de, (d88_error_message)
	jp		print_system

d88_default_name:
	db		0, "DUMP    D88"
d88_msg_name:
	db		"Error: Use an 8.3 filename. Temporary extension is reserved.", 13, 10, '$'
d88_msg_exists:
	db		"Error: Output or temporary file exists. No overwrite.", 13, 10, '$'
d88_msg_io:
	db		"Error: D88 file I/O failed. An incomplete temporary file may remain.", 13, 10, '$'
d88_msg_data:
	db		"Error: Invalid track data. D88 output stopped.", 13, 10, '$'
d88_msg_read:
	db		"Error: Track read failed. Temporary file kept.", 13, 10, '$'
d88_msg_read_errors:
	db		"Selected tracks read with errors.", 13, 10, '$'


d88_error_message:
	dw		d88_msg_io
d88_final_fcb:
	ds		D88_FCB_SIZE, 0

d88_sector_header:
	ds		16, 0

d88_header:
	ds		D88_HEADER_SIZE, 0


;-----------------------------------;
; HLregの32ビット値とDEの32ビット値を比較。CF=小、Z=一致。
; ポインタは保持する。BC/Aregを破壊。
; 入力条件: HLreg、DEreg: 比較対象のアドレス。
; 戻り値: Cy=1: HLreg側が小さい。Z: 等しい。HLreg・DEregを保存する。
;-----------------------------------;
d88_compare32:
	push	hl
	push	de

	ld		bc, 3
	add		hl, bc
	ex		de, hl
	add		hl, bc
	ex		de, hl

	ld		b, 4
d88_compare32_loop:
	ld		a, (de)
	ld		c, a
	ld		a, (hl)
	cp		c
	jr		nz, d88_compare32_end
;
	dec		hl
	dec		de
	djnz	d88_compare32_loop
;
d88_compare32_end:
	pop		de
	pop		hl
	ret
;
END
