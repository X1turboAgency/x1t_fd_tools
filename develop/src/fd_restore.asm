;-----------------------------------;
; D88から読み込んだIDを使いトラックをフォーマットし、データを書き戻す。
; データはWrite Sectorで転送する。F5/F6/F7を含むデータもそのまま書ける。
; GAPの長さ・CRCは再生成するため、磁気記録の完全な複製ではない。
; D88のID構成からトラックをフォーマットし、セクタデータを書き戻す。
;-----------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT
FD_FORMAT_DMA_PAD equ 128
;-----------------------------------;
; ID順にFDをフォーマットし、各セクタの元データを書き戻す。
; 入力条件: 選択トラックのID・データ・削除マークとFD設定。
; 戻り値: Cy=0: 書込み成功。Cy=1: 容量またはFDDエラー。
;-----------------------------------;
fd_restore_track:
	call	fd_build_format
	ret		c
;
	ld		de, cmd_write_msg
	call	setup_drive_param
	call	fdd_seek
	jp		nz, fd_restore_error
;
	ld		hl, format_data_buff
	ld		bc, (fd_format_length)
	call	fdd_write_track
	jp		nz, fd_restore_error
;
	ld		ix, read_id_list
	ld		iy, sector_status_buff
	ld		hl, read_track_buff
	ld		a, (sector_num)
	ld		(fd_sectors_left), a
;-----------------------------------;
; 削除データマークを設定し、セクタごとに元データを書き込む。
;-----------------------------------;
fd_restore_sector:
	; 削除データマークをWrite Sectorのbit0へ変換する。
	ld		a, (iy+SECTOR_DELETED_POS)
	or		a
	ld		a, 0
	jr		z, fd_restore_normal
;
	inc		a
fd_restore_normal:
	ld		(write_deleted), a
	ld		c, (ix+ID_LENGTH_L_POS)
	ld		b, (ix+ID_LENGTH_H_POS)
	push	hl
	push	bc
	push	ix
	push	iy
	ld		a, (ix+ID_R_POS)
	call	fdd_write_sector
	pop		iy
	pop		ix
	pop		bc
	pop		hl
	jp		nz, fd_restore_error
;
	add		hl, bc
	ld		de, ID_SIZE
	add		ix, de
	inc		iy
	ld		a, (fd_sectors_left)
	dec		a
	ld		(fd_sectors_left), a
	jr		nz, fd_restore_sector
;
	call	motor_off
	xor		a
	ret
;
fd_restore_error:
	push	af
	call	fdd_check_abort
	ld		hl, fd_msg_write
	jr		nc, fd_restore_error_message
;
	call	fdd_abort_command
	ld		hl, fdd_msg_access
fd_restore_error_message:
	ld		(d88_error_message), hl
	pop		af
	call	print_disk_stat
	call	motor_off
	scf
	ret
;
; フォーマットストリーム生成前に必要量を計算し、バッファを超えない。
;-----------------------------------;
; GAPとCRCを含むトラック記録容量を計算する。
; 入力条件: sector_num、read_id_list、media_type。
; 戻り値: Cy=0: 収録可能。Cy=1: 不正な個数または容量超過。
;-----------------------------------;
fd_validate_format:
	ld		a, (sector_num)
	or		a
	jp		z, fd_format_error
;
	cp		33
	jp		nc, fd_format_error
;
	ld		(fd_sectors_left), a
	ld		a, (media_type)
	cp		DISK_TYPE_2HD
	ld		hl, 32
	ld		bc, FORMAT_DATA_2D_MAX_SIZE
	ld		a, 24
	jr		nz, fd_format_parameters
;
	ld		hl, 146
	ld		bc, FORMAT_DATA_2HD_MAX_SIZE
	ld		a, 54
fd_format_parameters:
	ld		(fd_gap3), a
	ld		(fd_format_capacity), bc
	ld		ix, read_id_list
fd_format_size_loop:
	ld		c, (ix+ID_LENGTH_L_POS)
	ld		b, (ix+ID_LENGTH_H_POS)
	add		hl, bc
	jp		c, fd_format_error
;
	ld		a, (fd_gap3)
	add		a, 62
	ld		e, a
	ld		d, 0
	; F7はCRCの2バイトへ展開される。1セクタにつき2バイトを加算。
	add		hl, de
	jp		c, fd_format_error
;
	ld		de, ID_SIZE
	add		ix, de
	ld		a, (fd_sectors_left)
	dec		a
	ld		(fd_sectors_left), a
	jr		nz, fd_format_size_loop
;
	ld		de, (fd_format_capacity)
	or		a
	sbc		hl, de
	jp		nc, fd_format_error
;
	xor		a
	ret
;
; 事前検査では容量計算だけを行い、書込み時にだけストリームを作成する。
;-----------------------------------;
; 記録容量を確認し、Write Track用ストリームを生成する。
; 入力条件: sector_num、read_id_list、media_type。
; 戻り値: Cy=0: format_data_buffとfd_format_lengthを設定。Cy=1: 構成不正。
;-----------------------------------;
fd_build_format:
	call	fd_validate_format
	ret		c
;
	; INDEXでFDCが終了するまでDMAが枯渇しないようGAP4に余裕を持たせる。
	ld		hl, (fd_format_capacity)
	ld		de, FD_FORMAT_DMA_PAD
	add		hl, de
	ld		(fd_format_length), hl
	ld		de, format_data_buff
	ld		a, (media_type)
	cp		DISK_TYPE_2HD
	jr		z, fd_format_hd_gap
;
	ld		a, 04eh
	ld		bc, 32
	call	fd_format_fill
	jr		fd_format_ids
;
fd_format_hd_gap:
	ld		a, 04eh
	ld		bc, 80
	call	fd_format_fill
	xor		a
	ld		bc, 12
	call	fd_format_fill
	ld		a, 0f6h
	ld		bc, 3
	call	fd_format_fill
	ld		a, 0fch
	ld		(de), a
	inc		de
	ld		a, 04eh
	ld		bc, 50
	call	fd_format_fill
;-----------------------------------;
; IDとデータ領域を組み合わせ、フォーマットストリームを生成する。
;-----------------------------------;
fd_format_ids:
	ld		ix, read_id_list
	ld		a, (sector_num)
	ld		(fd_sectors_left), a
fd_format_sector:
	xor		a
	ld		bc, 12
	call	fd_format_fill
	ld		a, 0f5h
	ld		bc, 3
	call	fd_format_fill
	ld		a, 0feh
	ld		(de), a
	inc		de
	push	ix
	pop		hl
	ld		bc, 4
	ldir
	ld		a, 0f7h
	ld		(de), a
	inc		de
	ld		a, 04eh
	ld		bc, 22
	call	fd_format_fill
	xor		a
	ld		bc, 12
	call	fd_format_fill
	ld		a, 0f5h
	ld		bc, 3
	call	fd_format_fill
	ld		a, 0fbh
	ld		(de), a
	inc		de
	ld		a, 0e5h
	ld		c, (ix+ID_LENGTH_L_POS)
	ld		b, (ix+ID_LENGTH_H_POS)
	call	fd_format_fill
	ld		a, 0f7h
	ld		(de), a
	inc		de
	ld		a, (fd_gap3)
	ld		c, a
	ld		b, 0
	ld		a, 04eh
	call	fd_format_fill
	ld		bc, ID_SIZE
	add		ix, bc
	ld		a, (fd_sectors_left)
	dec		a
	ld		(fd_sectors_left), a
	jr		nz, fd_format_sector
;
	ld		hl, format_data_buff
	ld		bc, (fd_format_length)
	add		hl, bc
	or		a
	sbc		hl, de
	jp		c, fd_format_error
;
	ld		c, l
	ld		b, h
	ld		a, b
	or		c
	jr		z, fd_format_ready
;
	ld		a, 04eh
	call	fd_format_fill
fd_format_ready:
	xor		a
	ret
;
; DEregへAをBC回書く。HL/IX/IYregは保持する。BCreg=0では呼び出さない。
;-----------------------------------;
; 指定値でフォーマット領域の連続バイトを埋める。
; 入力条件: Areg: 値。DEreg: 書込み先。BCreg: バイト数（1以上）。
; 戻り値: DEreg: 書込み末尾の次。BCreg=0。AFreg・HLreg・IXreg・IYregを保存する。
;-----------------------------------;
fd_format_fill:
	ld		(de), a
	inc		de
	dec		bc
	push	af
	ld		a, b
	or		c
	jr		z, fd_format_fill_done
;
	pop		af
	jr		fd_format_fill
;
fd_format_fill_done:
	pop		af
	ret
;
fd_format_error:
	ld		hl, fd_msg_format
	ld		(d88_error_message), hl
	scf
	ret
;
fd_msg_write: db "Error: FD write failed.",13,10,'$'
fd_msg_format: db "Error: Sector layout exceeds track capacity.",13,10,'$'
fd_format_capacity: dw 0
fd_format_length: dw 0
fd_gap3: db 0
fd_sectors_left: db 0

;;    assert format_data_buff+FORMAT_DATA_2HD_MAX_SIZE+FD_FORMAT_DMA_PAD < 0cf00h

END
