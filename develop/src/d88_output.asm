;-----------------------------------;
; LSX-Dodgers用D88出力（MSX-DOS互換FCBランダムブロックI/O）。
; 公開ルーチンはすべて、成功時CF=0、失敗時CF=1を返す。
; 出力先は引数の指定ドライブ。省略時はカレントドライブ。
; 完成ファイル<name>.D88と同じ場所に、一時ファイル<name>.$$$を作成する。
; 既存の完成ファイル・一時ファイルは上書きしない。
; 一時ファイルへの保存、D88ヘッダの更新と完成ファイルへのリネームを行う。
;-----------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT

;-----------------------------------;
; 既存ファイルを検査し、一時D88を作成して仮ヘッダを保存する。
; 入力条件: FCB1のファイル名、media_type。
; 戻り値: Cy=0: 作成成功。Cy=1: 作成不可またはI/Oエラー。
;-----------------------------------;
d88_create:
	xor		a
	ld		(d88_opened), a
	ld		(d88_read_errors), a

	ld		hl, d88_msg_io
	ld		(d88_error_message), hl
	call	d88_prepare_name
	ret		c
;
	ld		de, d88_final_fcb
	call	d88_exists
	jp		c, d88_fail_exists
;
	call	d88_reset_temp
	ld		de, d88_temp_fcb
	call	d88_exists
	jp		c, d88_fail_exists
;
	call	d88_reset_temp
	ld		de, d88_temp_fcb
	ld		c, CMD_FILE_CREATE
	call	SYSTEM
	cp		0ffh
	jp		z, d88_fail_io
;
	ld		a, 1
	ld		(d88_opened), a
	ld		hl, 1
	ld		(d88_temp_fcb+14), hl ; one byte per record

	xor		a
	ld		hl, d88_temp_fcb+33
	ld		(hl), a
	inc		hl
	ld		(hl), a
	inc		hl
	ld		(hl), a
	inc		hl
	ld		(hl), a

	ld		hl, d88_header
	ld		de, d88_header+1
	ld		bc, D88_HEADER_SIZE-1
	ld		(hl), 0
	ldir

	ld		hl, d88_final_fcb+1
	ld		de, d88_header
	ld		bc, 8
	ldir

	ld		a, (media_type)
	ld		(d88_header+01bh), a
	ld		hl, D88_HEADER_SIZE
	ld		(d88_header+01ch), hl
	ld		de, d88_header
	ld		hl, D88_HEADER_SIZE

	call	d88_write_block
	ret		c
;
	ld		hl, d88_temp_fcb+33
	ld		de, d88_file_pos
	ld		bc, 4
	ldir

	xor		a
	ret

;-----------------------------------;
; 完成名を基に一時拡張子とFCB作業領域を設定する。
; 入力条件: d88_final_fcb。
; 戻り値: d88_temp_fcbを初期化する。フラグは判定に使用しない。
;-----------------------------------;
d88_reset_temp:
	ld		hl, d88_final_fcb
	ld		de, d88_temp_fcb
	ld		bc, 12
	ldir

	ld		hl, d88_temp_fcb+12
	call	d88_clear_fcb_work
	ld		hl, d88_temp_extension
	ld		de, d88_temp_fcb+9
	ld		bc, 3
	ldir

	ret

;-----------------------------------;
;	FBC内のワークをクリア
; ファイルの存在をオープンで検査し、開けたものは閉じる。
; 入力条件: DEreg: 未オープンのFCB。
; 戻り値: Cy=1: オープン成功で既存。Cy=0: オープン不可。
;-----------------------------------;
d88_exists:
	push	de
	ld		c, CMD_FILE_OPEN
	call	SYSTEM
	pop		de
	cp		0ffh
	jr		z, d88_not_found
;
	ld		c, CMD_FILE_CLOSE
	call	SYSTEM
	scf
	ret
;
d88_not_found:
	xor		a
	ret

;-----------------------------------;
; 取得した1トラックのセクタヘッダとデータを一時D88へ追記する。
; 入力条件: start_track_no、sector_num、ID・データ・状態の各バッファ。
; 戻り値: Cy=0: 保存成功。Cy=1: 不正データまたはI/Oエラー。
;-----------------------------------;
d88_write_track:
	ld		a, (start_track_no)
	cp		D88_TRACK_COUNT
	jp		nc, d88_fail_data
;
	ld		a, (sector_num)
	or		a
	jp		z, d88_fail_data
;
	cp		33
	jp		nc, d88_fail_data
;
	ld		(d88_sectors_left), a
	ld		hl, d88_file_pos
	ld		de, d88_track_start
	ld		bc, 4
	ldir

	ld		hl, read_id_list
	ld		(d88_id_ptr), hl
	ld		hl, sector_status_buff
	ld		(d88_status_ptr), hl
	ld		hl, read_track_buff
	ld		(d88_data_ptr), hl

d88_sector_loop:
	ld		hl, d88_sector_header
	ld		de, d88_sector_header+1
	ld		bc, 15
	ld		(hl), 0
	ldir

	ld		hl, (d88_id_ptr)
	ld		de, d88_sector_header
	ld		bc, 4
	ldir	; C,H,R,N

	inc		hl
	inc		hl ; ID CRC bytes 部分をスキップする。

	ld		c, (hl)
	inc		hl
	ld		b, (hl)
	inc		hl
	ld		(d88_id_ptr), hl
	ld		(d88_sector_header+14), bc
	ld		a, b
	or		c
	jp		z, d88_fail_data
;
	ld		hl, (d88_data_ptr)
	add		hl, bc
	jp		c, d88_fail_data
;
	ld		de, read_track_buff_max
	or		a
	sbc		hl, de
	jp		c, d88_sector_fits
;
	jp		nz, d88_fail_data
;

d88_sector_fits:
	ld		a, (sector_num)
	ld		(d88_sector_header+4), a
	ld		hl, (d88_status_ptr)
	ld		a, (hl)
	inc		hl
	ld		(d88_status_ptr), hl
	ld		b, a
	and		020h ; MB8877 Deleted Data Record
	jr		z, d88_not_deleted
;
	ld		a, 010h
	ld		(d88_sector_header+7), a
d88_not_deleted:
	ld		a, b
	and		09dh ; not ready / RNF / CRC / lost data / busy
	jr		z, d88_status_ready
;
	ld		a, 1
	ld		(d88_read_errors), a
	bit		7, b
	ld		a, 060h ; drive not ready
	jr		nz, d88_store_status
;
	bit		0, b
	ld		a, 050h ; command still busy: タイムアウト
	jr		nz, d88_store_status
;
	bit		4, b
	ld		a, 0c0h ; requested sector not found
	jr		nz, d88_store_status
;
	ld		a, 0b0h ; CRC or lost data: mark as bad data
d88_store_status:
	ld		(d88_sector_header+8), a
d88_status_ready:
	ld		de, d88_sector_header
	ld		hl, 16
	call	d88_write_block
	ret		c
;
	ld		de, (d88_data_ptr)
	ld		hl, (d88_sector_header+14)
	call	d88_write_block
	ret		c
;
	ld		hl, (d88_data_ptr)
	ld		bc, (d88_sector_header+14)
	add		hl, bc
	ld		(d88_data_ptr), hl
	ld		a, (d88_sectors_left)
	dec		a
	ld		(d88_sectors_left), a
	jp		nz, d88_sector_loop
;
	; 
	; トラック全体の書き込みが完了してから、テーブルのエントリを公開する。
	ld		a, (start_track_no)
	ld		l, a
	ld		h, 0
	add		hl, hl
	add		hl, hl
	ld		de, d88_header+020h
	add		hl, de
	ex		de, hl
	ld		hl, d88_track_start
	ld		bc, 4
	ldir
	ld		hl, d88_temp_fcb+33
	ld		de, d88_file_pos
	ld		bc, 4
	ldir
	xor		a
	ret

;-----------------------------------;
; 一時D88の現在のランダム位置へブロックを書き込む。
; 入力条件: DEreg: データ先頭。HLreg: バイト数。d88_temp_fcbはオープン済み。
; 戻り値: Cy=0: 書込み成功。Cy=1: I/Oエラー。
;-----------------------------------;
d88_write_block:
	push	hl
	ld		c, CMD_SET_DATA_ADRS
	call	SYSTEM
	pop		hl

	ld		de, d88_temp_fcb
	ld		c, CMD_WRITE_RAND_BLOCK
	call	SYSTEM
	or		a
	jp		nz, d88_fail_io
;
	ret

;-----------------------------------;
; D88ヘッダを更新し、一時ファイルを閉じて完成名へ変更する。
; 入力条件: オープン済みの一時D88と、完成したトラックテーブル・ファイル位置。
; 戻り値: Cy=0: 完成。Cy=1: I/Oまたはリネーム失敗。
;-----------------------------------;
d88_finish:
	ld		hl, d88_file_pos
	ld		de, d88_header+01ch
	ld		bc, 4
	ldir

	ld		hl, d88_temp_fcb+33
	ld		b, 4
	xor		a

;-----------------------------------;
; ヘッダ更新のため、出力FCBの32ビットランダム位置をゼロへ戻す。
;-----------------------------------;
d88_seek_zero:
	ld		(hl), a
	inc		hl
	djnz	d88_seek_zero
;
	ld		de, d88_header
	ld		hl, D88_HEADER_SIZE
	call	d88_write_block
	ret		c
;
	ld		de, d88_temp_fcb
	ld		c, CMD_FILE_CLOSE
	call	SYSTEM
	or		a
	jp		nz, d88_fail_io
;
	xor		a
	ld		(d88_opened), a
	call	d88_flush

	; リネームの直前に、最終的な名前を再確認する。
	ld		hl, d88_final_fcb+12
	call	d88_clear_fcb_work

	ld		de, d88_final_fcb
	call	d88_exists

	jp		c, d88_fail_exists
;
	call	d88_reset_temp

	ld		hl, d88_final_fcb

	; 第二FCBは+10h開始。新ファイル名の先頭は+11h。
	ld		de, d88_temp_fcb+010h
	ld		bc, 12
	ldir
	ld		hl, 0 ; 保存先にもカレントディレクトリを使用する。
	ld		(d88_temp_fcb+010h+14), hl
	ld		de, d88_temp_fcb

IF 1
	ld		c, CMD_FILE_RENAME
	call	SYSTEM
	or		a
	jp		nz, d88_fail_io
ENDIF
;
	call	d88_flush
	xor		a
	ret

;-----------------------------------;
; 異常終了時に一時D88を閉じ、完成名に変更せず残す。
; 入力条件: d88_opened、d88_temp_fcb。
; 戻り値: 後処理を実行。終了時フラグは成否判定に使用しない。
;-----------------------------------;
d88_abort:
	ld		a, (d88_opened)
	or		a
	jr		z, d88_abort_flush
;
	ld		de, d88_temp_fcb
	ld		c, CMD_FILE_CLOSE
	call	SYSTEM
	xor		a
	ld		(d88_opened), a
d88_abort_flush:
	call	d88_flush
	ret

;-----------------------------------;
; LSX-Dodgersのディスクバッファをフラッシュする。
; 入力条件: なし。
; 戻り値: OSの戻り値を返す。フラグは判定に使用しない。
;-----------------------------------;
d88_flush:
	ld		b, 0ffh
	ld		d, 0
	ld		c, CMD_FLUSH
	call	SYSTEM
	ret

d88_temp_extension:
	db		"$$$"

d88_opened:
	db 0
d88_read_errors:
	db 0
d88_sectors_left:
	db 0
d88_id_ptr:
	dw 0
d88_status_ptr:
	dw 0
d88_data_ptr:
	dw 0
d88_file_pos:
	ds 4,0
d88_track_start:
	ds 4,0

d88_temp_fcb:
	ds D88_FCB_SIZE,0

;-----------------------------------;
END

