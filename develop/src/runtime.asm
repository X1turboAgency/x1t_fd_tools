;-----------------------------------;
; 両コマンドで共用する実行時パラメータ
; 実行パラメータ、トラック範囲の進行と対応機種の判定を共用する。
;-----------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT
;-----------------------------------;

start_track_no: db 0
end_track_no:   db 0
sector_num:     db 0
drive_no:       db 0
media_type:     db 0

; Areg=現在の論理トラック。CF=1なら指定範囲の終端。
;-----------------------------------;
; 選択範囲内の次の論理トラックへ進む。
; 入力条件: start_track_no、end_track_no。
; 戻り値: Cy=0: 次の番号へ更新。Cy=1: 終端で更新しない。Areg: 現在番号。
;-----------------------------------;
next_track:
	ld		a, (end_track_no)
	ld		b, a
	ld		a, (start_track_no)
	cp		b
	ccf
	ret		c
;
	inc		a
	ld		(start_track_no), a
	or		a
	ret

;-----------------------------------;
; LSX-Dodgersの機種IDを先に確認し、X1系の場合だけVRAMでturbo判定する。
; CF=0: X1turbo。CF=1: 対応外メッセージを表示済み。
; 他機種ではX1固有のI/Oへアクセスしない。
; 入力条件: LSX-Dodgersのシステムコールが使用可能であること。
; 戻り値: Cy=0: X1turbo。Cy=1: 対応外メッセージを表示済み。
;-----------------------------------;
check_supported_platform:
	ld		hl, 0ffffh ; 未実装の呼出しでHLが保存された場合も対応外とする。
	ld		c, CMD_DOS_VERSION
	scf
	call	SYSTEM
	jr		c, platform_unsupported
;
	or		a
	jr		nz, platform_unsupported
;
	ld		a, l
	cp		LSX_MACHINE_X1
	jr		nz, platform_unsupported
;
	call	check_x1_x1turbo
	jr		nz, platform_unsupported
;
	xor		a
	ret
;
platform_unsupported:
	ld		de, str_platform_unsupported
	call	print_system
	scf
	ret
;
;-----------------------------------;
; X1/X1turbo判定 (テキストVRAMと漢字VRAMの独立性からX1とX1turboを判別する)
; 入力条件: X1系の機種IDを確認済みであること。
; 戻り値:
;	Zflag: X1turbo
;	NZflag: X1
;-----------------------------------;
check_x1_x1turbo:
	ld		de, 'T' << 8 | 'X'
	ld		bc, TEXT_VRAM_CK
;;	in		l,(c)	; 保持
	out		(c),d

	ld		b, KANJI_VRAM_CK >> 8
;;	in		h,(c)	; 保持
	out		(c),e

	ld		b, TEXT_VRAM_CK >> 8
	in		a,(c)
;;	out		(c),l

;;	ld		b, KANJI_VRAM >> 8
;;	out		(c),h

	cp		d
	ret

;
END
