"""Bit-accurate helpers for the documented 32-bit AER packet drafts."""

from __future__ import annotations

TYPE_RAW = 0b00
TYPE_MASK = 0b01
TYPE_BIN = 0b10
TYPE_SYNC = 0b11


def _check(name: str, value: int, bits: int) -> int:
    if not 0 <= value < (1 << bits):
        raise ValueError(f"{name}={value} does not fit in {bits} bits")
    return value


def pack_raw_v0(x: int, y: int, polarity: int, time: int, flag: int = 0) -> int:
    """Pack the currently implemented RAW v0 format."""

    return (
        (_check("x", x, 10) << 20)
        | (_check("y", y, 10) << 10)
        | (_check("polarity", polarity, 1) << 9)
        | (_check("time", time, 8) << 1)
        | _check("flag", flag, 1)
    )


def unpack_raw_v0(word: int) -> dict[str, int | str]:
    _check("word", word, 32)
    if word >> 30 != TYPE_RAW:
        raise ValueError("word is not a RAW v0 packet")
    return {
        "type": "RAW_V0",
        "x": (word >> 20) & 0x3FF,
        "y": (word >> 10) & 0x3FF,
        "polarity": (word >> 9) & 0x1,
        "time": (word >> 1) & 0xFF,
        "flag": word & 0x1,
    }


def pack_raw_128(
    x: int,
    y: int,
    polarity: int,
    delta_t: int,
    meta: int = 0,
) -> int:
    return (
        (TYPE_RAW << 30)
        | (_check("x", x, 7) << 23)
        | (_check("y", y, 7) << 16)
        | (_check("polarity", polarity, 1) << 15)
        | (_check("delta_t", delta_t, 8) << 7)
        | _check("meta", meta, 7)
    )


def pack_mask2_128(
    base_x: int,
    base_y: int,
    delta_t: int,
    on_mask: int,
    off_mask: int,
) -> int:
    if base_x % 2 or base_y % 2:
        raise ValueError("2x2 MASK base coordinates must be even")
    return (
        (TYPE_MASK << 30)
        | (_check("base_x", base_x, 7) << 22)
        | (_check("base_y", base_y, 7) << 15)
        | (_check("delta_t", delta_t, 7) << 8)
        | (_check("on_mask", on_mask, 4) << 4)
        | _check("off_mask", off_mask, 4)
    )


def pack_mask4_header_128(
    block_x: int,
    block_y: int,
    delta_t: int,
    sequence: int,
    meta: int = 0,
) -> int:
    return (
        (TYPE_MASK << 30)
        | (1 << 29)
        | (_check("block_x", block_x, 5) << 24)
        | (_check("block_y", block_y, 5) << 19)
        | (_check("delta_t", delta_t, 7) << 12)
        | (_check("sequence", sequence, 5) << 7)
        | _check("meta", meta, 7)
    )


def pack_mask4_body(on_mask: int, off_mask: int) -> int:
    return (
        _check("on_mask", on_mask, 16) << 16
    ) | _check("off_mask", off_mask, 16)


def pack_bin_128(
    size: int,
    base_x: int,
    base_y: int,
    on_count: int,
    off_count: int,
    delta_t: int,
) -> int:
    if size not in (2, 4):
        raise ValueError("BIN size must be 2 or 4")
    if base_x % size or base_y % size:
        raise ValueError("BIN base coordinates must align to its size")
    size_bit = 0 if size == 2 else 1
    return (
        (TYPE_BIN << 30)
        | (size_bit << 29)
        | (_check("base_x", base_x, 7) << 22)
        | (_check("base_y", base_y, 7) << 15)
        | (_check("on_count", on_count, 5) << 10)
        | (_check("off_count", off_count, 5) << 5)
        | _check("delta_t", delta_t, 5)
    )


def pack_sync(payload: int) -> int:
    return (TYPE_SYNC << 30) | _check("payload", payload, 30)


def decode_adaptive_word(word: int) -> dict[str, int | str]:
    """Decode a standalone header/data word.

    A 4x4 MASK body has no standalone type bits and must be decoded with the
    preceding header by decode_mask4_pair().
    """

    _check("word", word, 32)
    packet_type = word >> 30
    if packet_type == TYPE_RAW:
        return {
            "type": "RAW",
            "x": (word >> 23) & 0x7F,
            "y": (word >> 16) & 0x7F,
            "polarity": (word >> 15) & 0x1,
            "delta_t": (word >> 7) & 0xFF,
            "meta": word & 0x7F,
        }
    if packet_type == TYPE_MASK:
        size_bit = (word >> 29) & 0x1
        if size_bit == 0:
            return {
                "type": "MASK2",
                "base_x": (word >> 22) & 0x7F,
                "base_y": (word >> 15) & 0x7F,
                "delta_t": (word >> 8) & 0x7F,
                "on_mask": (word >> 4) & 0xF,
                "off_mask": word & 0xF,
            }
        return {
            "type": "MASK4_HEADER",
            "block_x": (word >> 24) & 0x1F,
            "block_y": (word >> 19) & 0x1F,
            "delta_t": (word >> 12) & 0x7F,
            "sequence": (word >> 7) & 0x1F,
            "meta": word & 0x7F,
        }
    if packet_type == TYPE_BIN:
        size = 4 if ((word >> 29) & 0x1) else 2
        return {
            "type": f"BIN{size}",
            "base_x": (word >> 22) & 0x7F,
            "base_y": (word >> 15) & 0x7F,
            "on_count": (word >> 10) & 0x1F,
            "off_count": (word >> 5) & 0x1F,
            "delta_t": word & 0x1F,
        }
    return {"type": "SYNC", "payload": word & 0x3FFFFFFF}


def decode_mask4_pair(header: int, body: int) -> dict[str, int | str]:
    decoded = decode_adaptive_word(header)
    if decoded["type"] != "MASK4_HEADER":
        raise ValueError("first word is not a 4x4 MASK header")
    _check("body", body, 32)
    return {
        **decoded,
        "type": "MASK4",
        "on_mask": (body >> 16) & 0xFFFF,
        "off_mask": body & 0xFFFF,
    }
