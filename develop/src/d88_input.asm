;-----------------------------------;
; D88の入力。単一イメージを扱い、選択トラックを全検査してからFDへ書く。
; ランダムブロック読み取りは1バイトを1レコードとする。
; 未収録トラックはsector_num=0で返し、FD上の同じトラックを変更しない。
; フォーマット領域を一時入力バッファとして共用し、1トラックを1回で読む。
; セクタ展開が完了してからフォーマットを生成するため、領域は競合しない。
; D88トラックを一括入力し、境界とセクタ構造を検査して展開する。
;-----------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT
D88_STAGE_BASE equ format_data_buff
D88_STAGE_MAX_SIZE equ FORMAT_DATA_2HD_MAX_SIZE
;-----------------------------------;
;-----------------------------------;
; 入力D88を開き、サイズと指定メディアをヘッダと照合する。
; 入力条件: d88_final_fcb、media_type。
; 戻り値: Cy=0: 入力を準備済み。Cy=1: オープン・形式・メディアのエラー。
;-----------------------------------;
d88_input_open:
	xor		a
	ld		(d88_input_opened), a
	ld		hl, d88_msg_input_io
	ld		(d88_error_message), hl
	ld		hl, d88_final_fcb
	ld		de, d88_input_fcb
	ld		bc, 12
	ldir
	ld		hl, d88_input_fcb+12
	call	d88_clear_fcb_work
	ld		de, d88_input_fcb
	ld		c, CMD_FILE_OPEN
	call	SYSTEM
	cp		0ffh
	jp		z, d88_input_io_error
;
	ld		a, 1
	ld		(d88_input_opened), a
	ld		hl, d88_input_fcb+16
	ld		de, d88_input_size
	ld		bc, 4
	ldir
	ld		hl, d88_input_size
	ld		de, d88_input_limit
	ld		bc, 4
	ldir
	ld		hl, 1
	ld		(d88_input_fcb+14), hl
	ld		hl, 0
	ld		(d88_input_fcb+33), hl
	ld		(d88_input_fcb+35), hl
	ld		de, d88_header
	ld		hl, D88_HEADER_SIZE
	call	d88_input_read
	ret		c
;
	; 連結D88は別イメージを誤って書き込まないよう受け付けない。
	ld		hl, d88_header+01ch
	ld		de, d88_input_size
	call	d88_compare32
	jp		nz, d88_input_format_error
;
	ld		a, (media_type)
	ld		b, a
	ld		a, (d88_header+01bh)
	cp		b
	jp		nz, d88_input_media_error
;
	xor		a
	ret
;
; 開いている入力ファイルだけを閉じる。
;-----------------------------------;
; 入力D88が開いている場合だけ閉じる。
; 入力条件: d88_input_opened、d88_input_fcb。
; 戻り値: Cy=0: クローズ済みまたは未オープン。Cy=1: クローズ失敗。
;-----------------------------------;
d88_input_close:
	ld		a, (d88_input_opened)
	or		a
	ret		z
;
	ld		de, d88_input_fcb
	ld		c, CMD_FILE_CLOSE
	call	SYSTEM
	or		a
	jp		nz, d88_input_io_error
;
	xor		a
	ld		(d88_input_opened), a
	ret
;
;-----------------------------------;
; 元のエラーメッセージを保存して入力ファイルを閉じる。
; 入力条件: d88_error_messageと入力FCBの状態。
; 戻り値: d88_error_messageを保存する。Cyはクローズ処理の結果。
;-----------------------------------;
d88_input_close_preserve:
	ld		hl, (d88_error_message)
	push	hl
	call	d88_input_close
	pop		hl
	ld		(d88_error_message), hl
	ret
;
; DEreg=読込先、HLreg=バイト数。読込範囲は現在のトラック境界以下。
;-----------------------------------;
; 現在のトラック境界を超えない範囲でランダムブロックを読む。
; 入力条件: DEreg: 読込み先。HLreg: バイト数。入力FCBとd88_input_limit。
; 戻り値: Cy=0: 指定バイト数を取得。Cy=1: 境界超過またはI/Oエラー。
;-----------------------------------;
d88_input_read:
	ld		(d88_read_count), hl
	push	de
	ld		de, (d88_input_fcb+33)
	add		hl, de
	ld		(d88_read_end), hl
	ld		hl, (d88_input_fcb+35)
	ld		de, 0
	adc		hl, de
	ld		(d88_read_end+2), hl
	pop		de
	jp		c, d88_input_format_error
;
	push	de
	ld		hl, d88_read_end
	ld		de, d88_input_limit
	call	d88_compare32
	pop		de
	jr		c, d88_input_read_fits
;
	jp		nz, d88_input_format_error
;
d88_input_read_fits:
	ld		c, CMD_SET_DATA_ADRS
	call	SYSTEM
	ld		de, d88_input_fcb
	ld		hl, (d88_read_count)
	ld		c, CMD_READ_RAND_BLOCK
	call	SYSTEM
	or		a
	jp		nz, d88_input_io_error
;
	ld		de, (d88_read_count)
	or		a
	sbc		hl, de
	jp		nz, d88_input_io_error
;
	xor		a
	ret
;
; 対象範囲の全トラックを検査する。FDへのコマンドは発行しない。
;-----------------------------------;
; 選択範囲を全検査し、FD書込み前に構造と記録容量を確認する。
; 入力条件: オープン済みD88とstart_track_no・end_track_no。
; 戻り値: Cy=0: 検査合格。Cy=1: 不正または空の範囲。開始番号を復元する。
;-----------------------------------;
d88_preflight:
	ld		de, d88_msg_checking
	call	print_system
	ld		a, (start_track_no)
	ld		(d88_first_track), a
	xor		a
	ld		(d88_present_tracks), a
;-----------------------------------;
; 検査中の番号を表示して次のトラックを検証する。
;-----------------------------------;
d88_preflight_loop:
	ld		de, d88_msg_check_track
	call	print_system
	ld		a, (start_track_no)
	call	print_decimal
	ld		de, confirm_msg_slash
	call	print_system
	ld		a, (end_track_no)
	call	print_decimal
	call	print_crlf
	call	d88_load_track
	jr		c, d88_preflight_exit
;
	ld		a, (sector_num)
	or		a
	jr		z, d88_preflight_next
;
	ld		a, 1
	ld		(d88_present_tracks), a
	call	fd_validate_format
	jr		c, d88_preflight_exit
;
d88_preflight_next:
	call	next_track
	jr		nc, d88_preflight_loop
;
	ld		a, (d88_present_tracks)
	or		a
	jr		nz, d88_preflight_ok
;
	ld		hl, d88_msg_empty
	ld		(d88_error_message), hl
	scf
	jr		d88_preflight_exit
;
d88_preflight_ok:
	ld		de, d88_msg_check_ok
	call	print_system
	xor		a
d88_preflight_exit:
	push	af
	ld		a, (d88_first_track)
	ld		(start_track_no), a
	pop		af
	ret
;
; テーブルの論理番号からロードする。C/Hでトラックを詰め直さない。
;-----------------------------------;
; テーブル位置から1トラックを一括読込みし、IDとデータを展開する。
; 入力条件: start_track_no、入力D88ヘッダとFCB。
; 戻り値: Cy=0: 展開成功。未収録はsector_num=0。Cy=1: 形式・I/Oエラー。
;-----------------------------------;
d88_load_track:
	xor		a
	ld		(sector_num), a
	ld		a, (start_track_no)
	ld		l, a
	ld		h, 0
	add		hl, hl
	add		hl, hl
	ld		de, d88_header+020h
	add		hl, de
	ld		a, (hl)
	inc		hl
	or		(hl)
	inc		hl
	or		(hl)
	inc		hl
	or		(hl)
	ret		z
;
	dec		hl
	dec		hl
	dec		hl
	ld		de, d88_track_offset
	ld		bc, 4
	ldir
	ld		hl, d88_track_offset
	ld		de, d88_min_offset
	call	d88_compare32
	jp		c, d88_input_format_error
;
	ld		de, d88_input_size
	call	d88_compare32
	jp		nc, d88_input_format_error
;
	; 次の物理位置を持つテーブル項目、またはファイル末尾を境界とする。
	; テーブル項目の物理的な並び順には依存しない。
	ld		hl, d88_input_size
	ld		de, d88_input_limit
	ld		bc, 4
	ldir
	ld		hl, d88_header+020h
	ld		(d88_table_ptr), hl
	ld		a, D88_TRACK_COUNT
	ld		(d88_table_left), a
	xor		a
	ld		(d88_same_offset), a
;-----------------------------------;
; 全テーブルから次の物理位置を探し、同一位置の重複も拒否する。
;-----------------------------------;
d88_find_bound:
	ld		hl, (d88_table_ptr)
	ld		de, d88_track_offset
	call	d88_compare32
	jr		z, d88_bound_equal
;
	jr		c, d88_bound_next
;
	ld		de, d88_input_limit
	call	d88_compare32
	jr		nc, d88_bound_next
;
	ld		bc, 4
	ldir
	jr		d88_bound_next
;
d88_bound_equal:
	ld		a, (d88_same_offset)
	inc		a
	ld		(d88_same_offset), a
	cp		2
	jp		nc, d88_input_format_error
;
d88_bound_next:
	ld		hl, (d88_table_ptr)
	ld		de, 4
	add		hl, de
	ld		(d88_table_ptr), hl
	ld		a, (d88_table_left)
	dec		a
	ld		(d88_table_left), a
	jr		nz, d88_find_bound
;
	ld		hl, d88_track_offset
	ld		de, d88_input_fcb+33
	ld		bc, 4
	ldir
	; トラック境界との差を32ビットで求め、作業領域を超える入力を拒否する。
	ld		hl, (d88_input_limit)
	ld		de, (d88_track_offset)
	or		a
	sbc		hl, de
	ld		(d88_stage_count), hl
	ld		hl, (d88_input_limit+2)
	ld		de, (d88_track_offset+2)
	sbc		hl, de
	jp		nz, d88_input_format_error
;
	ld		hl, (d88_stage_count)
	ld		de, D88_STAGE_MAX_SIZE+1
	or		a
	sbc		hl, de
	jp		nc, d88_input_format_error
;
	ld		hl, (d88_stage_count)
	ld		de, D88_STAGE_BASE
	call	d88_input_read
	ret		c
;
	ld		hl, D88_STAGE_BASE
	ld		(d88_stage_ptr), hl
	ld		de, (d88_stage_count)
	add		hl, de
	ld		(d88_stage_end), hl
	ld		hl, read_id_list
	ld		(d88_load_id), hl
	ld		hl, read_track_buff
	ld		(d88_load_data), hl
	ld		hl, sector_status_buff
	ld		(d88_load_status), hl
	xor		a
	ld		(d88_loaded_sectors), a
;-----------------------------------;
; RAM上のセクタヘッダを検査し、ID・削除マーク・データを展開する。
;-----------------------------------;
d88_load_sector:
	ld		de, d88_sector_header
	ld		hl, 16
	call	d88_stage_read
	ret		c
;
	ld		a, (d88_sector_header+5)
	or		a
	jp		nz, d88_input_format_error
;
	ld		a, (d88_sector_header+4)
	or		a
	jp		z, d88_input_format_error
;
	cp		33
	jp		nc, d88_input_format_error
;
	ld		b, a
	ld		a, (sector_num)
	or		a
	jr		nz, d88_check_sector_count
;
	ld		a, b
	ld		(sector_num), a
d88_check_sector_count:
	cp		b
	jp		nz, d88_input_format_error
;
	; MFM・正常セクタ・128～1024バイトだけを書き戻す。
	ld		a, (d88_sector_header+6)
	or		a
	jp		nz, d88_input_unsupported
;
	ld		a, (d88_sector_header+8)
	or		a
	jp		nz, d88_input_unsupported
;
	ld		a, (d88_sector_header+7)
	or		a
	jr		z, d88_check_chrn
;
	cp		010h
	jp		nz, d88_input_unsupported
;
d88_check_chrn:
	ld		a, (start_track_no)
	srl		a
	ld		b, a
	ld		a, (d88_sector_header)
	cp		b
	jp		nz, d88_input_unsupported
;
	ld		a, (start_track_no)
	and		1
	ld		b, a
	ld		a, (d88_sector_header+1)
	cp		b
	jp		nz, d88_input_unsupported
;
	ld		a, (d88_sector_header+3)
	cp		4
	jp		nc, d88_input_unsupported
;
	call	get_sector_length
	ld		hl, (d88_sector_header+14)
	or		a
	sbc		hl, bc
	jp		nz, d88_input_unsupported
;
	ld		hl, (d88_load_data)
	add		hl, bc
	jp		c, d88_input_format_error
;
	ld		de, read_track_buff_max
	or		a
	sbc		hl, de
	jr		c, d88_load_data_fits
;
	jp		nz, d88_input_format_error
;
d88_load_data_fits:
	; ID内のF5以上はWrite Track制御値と紛れるため拒否する。
	ld		a, (d88_sector_header+2)
	cp		0f5h
	jp		nc, d88_input_unsupported
;
	; 同じRの重複はType-II書込みで識別できないので拒否する。
	ld		a, (d88_loaded_sectors)
	or		a
	jr		z, d88_store_id
;
	ld		b, a
	ld		hl, read_id_list+2
	ld		a, (d88_sector_header+2)
d88_check_duplicate:
	cp		(hl)
	jp		z, d88_input_unsupported
;
	ld		de, 8
	add		hl, de
	djnz	d88_check_duplicate
;
d88_store_id:
	ld		hl, d88_sector_header
	ld		de, (d88_load_id)
	ld		bc, 4
	ldir
	xor		a
	ld		(de), a
	inc		de
	ld		(de), a
	inc		de
	ld		hl, d88_sector_header+14
	ld		bc, 2
	ldir
	ld		(d88_load_id), de
	ld		hl, (d88_load_status)
	ld		a, (d88_sector_header+7)
	ld		(hl), a
	inc		hl
	ld		(d88_load_status), hl
	ld		de, (d88_load_data)
	ld		hl, (d88_sector_header+14)
	call	d88_stage_read
	ret		c
;
	ld		hl, (d88_load_data)
	ld		de, (d88_sector_header+14)
	add		hl, de
	ld		(d88_load_data), hl
	ld		a, (d88_loaded_sectors)
	inc		a
	ld		(d88_loaded_sectors), a
	ld		b, a
	ld		a, (sector_num)
	cp		b
	jp		nz, d88_load_sector
;
	ld		hl, (d88_stage_ptr)
	ld		de, (d88_stage_end)
	or		a
	sbc		hl, de
	jp		nz, d88_input_format_error
;
	xor		a
	ret
;
; DEreg=展開先、HLreg=バイト数。一括入力済みの範囲だけをコピーする。
; ファイル位置とRAM上の展開位置を混同しない。終端も別途完全一致を検査する。
;-----------------------------------;
; 一括取得済みのRAM領域からセクタヘッダまたはデータを展開する。
; 入力条件: DEreg: 展開先。HLreg: バイト数（1以上）。d88_stage_ptr・end。
; 戻り値: Cy=0: 展開して位置を更新。Cy=1: RAM内の境界超過。
;-----------------------------------;
d88_stage_read:
	ld		c, l
	ld		b, h
	ld		hl, (d88_stage_ptr)
	add		hl, bc
	jp		c, d88_input_format_error
;
	push	de
	ld		de, (d88_stage_end)
	or		a
	sbc		hl, de
	pop		de
	jr		c, d88_stage_fits
;
	jp		nz, d88_input_format_error
;
d88_stage_fits:
	ld		hl, (d88_stage_ptr)
	ldir
	ld		(d88_stage_ptr), hl
	xor		a
	ret
;
d88_input_io_error:
	ld		hl, d88_msg_input_io
	jr		d88_input_error
;
d88_input_format_error:
	ld		hl, d88_msg_format
	jr		d88_input_error
;
d88_input_media_error:
	ld		hl, d88_msg_media
	jr		d88_input_error
;
d88_input_unsupported:
	ld		hl, d88_msg_unsupported
d88_input_error:
	ld		(d88_error_message), hl
	scf
	ret
;
d88_msg_checking: db "Checking D88 (no FD access)...",13,10,END_CODE
d88_msg_check_track: db "Check track: ",END_CODE
d88_msg_check_ok: db "D88 check OK.",13,10,END_CODE
d88_msg_input_io: db "Error: Input D88 read or close failed.",13,10,END_CODE
d88_msg_format: db "Error: Invalid D88 size, track offset or sector layout.",13,10,END_CODE
d88_msg_media: db "Error: Selected media does not match D88 header.",13,10,END_CODE
d88_msg_unsupported: db "Error: Unsupported sector (FM, CHRN, duplicate R or CRC status).",13,10,END_CODE
d88_msg_empty: db "Error: No recorded tracks in selected range.",13,10,END_CODE
d88_input_opened: db 0
d88_first_track: db 0
d88_present_tracks: db 0
d88_table_left: db 0
d88_same_offset: db 0
d88_loaded_sectors: db 0
d88_stage_count: dw 0
d88_stage_ptr: dw 0
d88_stage_end: dw 0
d88_read_count: dw 0
d88_table_ptr: dw 0
d88_load_id: dw 0
d88_load_data: dw 0
d88_load_status: dw 0
d88_min_offset: dw D88_HEADER_SIZE,0
d88_input_size: ds 4,0
d88_input_limit: ds 4,0
d88_track_offset: ds 4,0
d88_read_end: ds 4,0
d88_input_fcb: ds D88_FCB_SIZE,0
END
