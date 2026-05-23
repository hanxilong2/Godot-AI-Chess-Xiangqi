extends RefCounted
class_name XiangqiConstants

const RED := 0
const BLACK := 1

const BOARD_FILES := 9
const BOARD_RANKS := 10
const BOARD_SIZE := BOARD_FILES * BOARD_RANKS

const FILE_NAMES := ["a", "b", "c", "d", "e", "f", "g", "h", "i"]

const PIECE_TYPES := ["k", "a", "e", "h", "r", "c", "p"]
const PIECE_NAMES := {
	"k": "general",
	"a": "advisor",
	"e": "elephant",
	"h": "horse",
	"r": "rook",
	"c": "cannon",
	"p": "soldier",
}
const VALID_PIECES := [
	"k", "a", "e", "h", "r", "c", "p",
	"K", "A", "E", "H", "R", "C", "P",
]
const FEN_PIECE_ALIASES := {
	"n": "h",
	"N": "H",
	"b": "e",
	"B": "E",
}

const START_FEN := "rheakaehr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RHEAKAEHR w"

const FLAG_CAPTURE := 1 << 0
const FLAG_CHECK := 1 << 1
const FLAG_CHECKMATE := 1 << 2
const FLAG_SPECIAL := 1 << 3

static func side_to_token(side: int) -> String:
	return "w" if side == RED else "b"

static func token_to_side(token: String) -> int:
	var normalized := token.strip_edges().to_lower()
	if normalized in ["b", "black"]:
		return BLACK
	return RED

static func is_valid_side_token(token: String) -> bool:
	var normalized := token.strip_edges().to_lower()
	return normalized in ["w", "white", "r", "red", "b", "black"]

static func other_side(side: int) -> int:
	return BLACK if side == RED else RED

static func normalize_piece(piece: String) -> String:
	if piece.length() != 1:
		return ""
	var normalized := piece.substr(0, 1)
	return normalized if VALID_PIECES.has(normalized) else ""

static func is_valid_piece(piece: String) -> bool:
	return !normalize_piece(piece).is_empty()

static func normalize_fen_piece(piece: String) -> String:
	if piece.length() != 1:
		return ""
	var token := piece.substr(0, 1)
	return normalize_piece(String(FEN_PIECE_ALIASES.get(token, token)))

static func is_valid_fen_piece(piece: String) -> bool:
	return !normalize_fen_piece(piece).is_empty()

static func side_from_piece(piece: String) -> int:
	if piece.is_empty():
		return RED
	return RED if piece == piece.to_upper() else BLACK

static func piece_type(piece: String) -> String:
	return piece.to_lower()

static func piece_name(piece: String) -> String:
	return PIECE_NAMES.get(piece_type(piece), "")

static func is_in_black_palace(file: int, rank: int) -> bool:
	return file >= 3 and file <= 5 and rank >= 0 and rank <= 2

static func is_in_red_palace(file: int, rank: int) -> bool:
	return file >= 3 and file <= 5 and rank >= 7 and rank <= 9

static func is_in_palace(side: int, file: int, rank: int) -> bool:
	return is_in_red_palace(file, rank) if side == RED else is_in_black_palace(file, rank)

static func has_crossed_river(side: int, rank: int) -> bool:
	return rank <= 4 if side == RED else rank >= 5
