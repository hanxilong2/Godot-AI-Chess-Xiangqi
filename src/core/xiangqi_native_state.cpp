#include "xiangqi_native_state.hpp"

#include <algorithm>
#include <cctype>

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

XiangqiNativeStateCpp::XiangqiNativeStateCpp()
{
	clear();
}

void XiangqiNativeStateCpp::clear()
{
	board.fill(EMPTY);
	side_to_move = RED;
	halfmove_clock = 0;
	fullmove_number = 1;
}

void XiangqiNativeStateCpp::load_board(const Array &board_array, int side, int halfmove, int fullmove)
{
	board.fill(EMPTY);
	const int limit = std::min<int>(BOARD_SIZE, board_array.size());
	for (int index = 0; index < limit; index++)
	{
		const String piece_text = board_array[index];
		board[index] = normalize_piece(piece_text);
	}

	set_side_to_move(side);
	halfmove_clock = std::max(0, halfmove);
	fullmove_number = std::max(1, fullmove);
}

Array XiangqiNativeStateCpp::get_board_array() const
{
	Array result;
	for (int index = 0; index < BOARD_SIZE; index++)
	{
		result.push_back(piece_to_string(board[index]));
	}
	return result;
}

int XiangqiNativeStateCpp::get_side_to_move() const
{
	return side_to_move;
}

void XiangqiNativeStateCpp::set_side_to_move(int side)
{
	side_to_move = side == RED ? RED : BLACK;
}

int XiangqiNativeStateCpp::get_halfmove_clock() const
{
	return halfmove_clock;
}

void XiangqiNativeStateCpp::set_halfmove_clock(int value)
{
	halfmove_clock = std::max(0, value);
}

int XiangqiNativeStateCpp::get_fullmove_number() const
{
	return fullmove_number;
}

void XiangqiNativeStateCpp::set_fullmove_number(int value)
{
	fullmove_number = std::max(1, value);
}

bool XiangqiNativeStateCpp::has_piece_at(int index) const
{
	return is_valid_index(index) && board[index] != EMPTY;
}

bool XiangqiNativeStateCpp::is_empty_at(int index) const
{
	return !has_piece_at(index);
}

String XiangqiNativeStateCpp::get_piece_at(int index) const
{
	if (!is_valid_index(index))
	{
		return "";
	}
	return piece_to_string(board[index]);
}

void XiangqiNativeStateCpp::set_piece_at(int index, const String &piece_text)
{
	if (!is_valid_index(index))
	{
		return;
	}
	board[index] = normalize_piece(piece_text);
}

String XiangqiNativeStateCpp::remove_piece_at(int index)
{
	if (!is_valid_index(index))
	{
		return "";
	}

	const char removed = board[index];
	board[index] = EMPTY;
	return piece_to_string(removed);
}

PackedInt32Array XiangqiNativeStateCpp::apply_move(int from_index, int to_index, const String &piece_text, int flags)
{
	if (!is_valid_index(from_index) || !is_valid_index(to_index))
	{
		return encode_move_result(from_index, to_index, EMPTY, EMPTY, flags);
	}

	char piece = normalize_piece(piece_text);
	if (piece == EMPTY)
	{
		piece = board[from_index];
	}

	if (piece == EMPTY)
	{
		return encode_move_result(from_index, to_index, EMPTY, EMPTY, flags);
	}

	const char captured_piece = board[to_index];
	if (captured_piece != EMPTY)
	{
		flags |= FLAG_CAPTURE;
	}

	board[from_index] = EMPTY;
	board[to_index] = piece;
	halfmove_clock = captured_piece != EMPTY || piece_type(piece) == 'p' ? 0 : halfmove_clock + 1;

	if (side_to_move == BLACK)
	{
		fullmove_number++;
	}

	side_to_move = other_side(side_to_move);
	return encode_move_result(from_index, to_index, piece, captured_piece, flags);
}

PackedInt32Array XiangqiNativeStateCpp::undo_move(int from_index, int to_index, const String &piece_text, const String &captured_piece_text, int flags)
{
	const char piece = normalize_piece(piece_text);
	const char captured_piece = normalize_piece(captured_piece_text);

	if (is_valid_index(from_index) && is_valid_index(to_index) && piece != EMPTY)
	{
		board[from_index] = piece;
		board[to_index] = captured_piece;
	}

	if (side_to_move == RED && fullmove_number > 1)
	{
		fullmove_number--;
	}

	side_to_move = other_side(side_to_move);
	halfmove_clock = 0;
	return encode_move_result(from_index, to_index, piece, captured_piece, flags);
}

int XiangqiNativeStateCpp::find_piece(const String &piece_text) const
{
	const char piece = normalize_piece(piece_text);
	if (piece == EMPTY)
	{
		return -1;
	}

	for (int index = 0; index < BOARD_SIZE; index++)
	{
		if (board[index] == piece)
		{
			return index;
		}
	}
	return -1;
}

int XiangqiNativeStateCpp::find_general(int side) const
{
	return find_piece(side == RED ? "K" : "k");
}

int XiangqiNativeStateCpp::get_piece_side(int index) const
{
	if (!is_valid_index(index) || board[index] == EMPTY)
	{
		return RED;
	}
	return side_from_piece(board[index]);
}

PackedInt32Array XiangqiNativeStateCpp::get_indices_for_side(int side) const
{
	PackedInt32Array indices;
	for (int index = 0; index < BOARD_SIZE; index++)
	{
		if (board[index] != EMPTY && side_from_piece(board[index]) == side)
		{
			indices.push_back(index);
		}
	}
	return indices;
}

int XiangqiNativeStateCpp::get_piece_count() const
{
	int count = 0;
	for (char piece : board)
	{
		if (piece != EMPTY)
		{
			count++;
		}
	}
	return count;
}

Ref<XiangqiNativeStateCpp> XiangqiNativeStateCpp::duplicate_state() const
{
	Ref<XiangqiNativeStateCpp> copy;
	copy.instantiate();
	copy->board = board;
	copy->side_to_move = side_to_move;
	copy->halfmove_clock = halfmove_clock;
	copy->fullmove_number = fullmove_number;
	return copy;
}

const std::array<char, XiangqiNativeStateCpp::BOARD_SIZE> &XiangqiNativeStateCpp::get_board_data() const
{
	return board;
}

int XiangqiNativeStateCpp::get_side_to_move_value() const
{
	return side_to_move;
}

char XiangqiNativeStateCpp::normalize_piece(const String &piece_text)
{
	if (piece_text.length() < 1)
	{
		return EMPTY;
	}

	const char32_t codepoint = piece_text[0];
	if (codepoint < 0 || codepoint > 127)
	{
		return EMPTY;
	}

	const char piece = static_cast<char>(codepoint);
	return is_valid_piece(piece) ? piece : EMPTY;
}

bool XiangqiNativeStateCpp::is_valid_piece(char piece)
{
	switch (piece_type(piece))
	{
		case 'k':
		case 'a':
		case 'e':
		case 'h':
		case 'r':
		case 'c':
		case 'p':
			return true;
		default:
			return false;
	}
}

String XiangqiNativeStateCpp::piece_to_string(char piece)
{
	return piece == EMPTY ? String() : String::chr(static_cast<int64_t>(piece));
}

int XiangqiNativeStateCpp::other_side(int side)
{
	return side == RED ? BLACK : RED;
}

int XiangqiNativeStateCpp::side_from_piece(char piece)
{
	return std::isupper(static_cast<unsigned char>(piece)) ? RED : BLACK;
}

char XiangqiNativeStateCpp::piece_type(char piece)
{
	return static_cast<char>(std::tolower(static_cast<unsigned char>(piece)));
}

bool XiangqiNativeStateCpp::is_valid_index(int index)
{
	return index >= 0 && index < BOARD_SIZE;
}

PackedInt32Array XiangqiNativeStateCpp::encode_move_result(int from_index, int to_index, char piece, char captured_piece, int flags) const
{
	PackedInt32Array encoded;
	encoded.push_back(from_index);
	encoded.push_back(to_index);
	encoded.push_back(piece);
	encoded.push_back(captured_piece);
	encoded.push_back(flags);
	encoded.push_back(side_to_move);
	encoded.push_back(halfmove_clock);
	encoded.push_back(fullmove_number);
	return encoded;
}

void XiangqiNativeStateCpp::_bind_methods()
{
	ClassDB::bind_method(D_METHOD("clear"), &XiangqiNativeStateCpp::clear);
	ClassDB::bind_method(D_METHOD("load_board", "board_array", "side", "halfmove", "fullmove"), &XiangqiNativeStateCpp::load_board);
	ClassDB::bind_method(D_METHOD("get_board_array"), &XiangqiNativeStateCpp::get_board_array);
	ClassDB::bind_method(D_METHOD("get_side_to_move"), &XiangqiNativeStateCpp::get_side_to_move);
	ClassDB::bind_method(D_METHOD("set_side_to_move", "side"), &XiangqiNativeStateCpp::set_side_to_move);
	ClassDB::bind_method(D_METHOD("get_halfmove_clock"), &XiangqiNativeStateCpp::get_halfmove_clock);
	ClassDB::bind_method(D_METHOD("set_halfmove_clock", "value"), &XiangqiNativeStateCpp::set_halfmove_clock);
	ClassDB::bind_method(D_METHOD("get_fullmove_number"), &XiangqiNativeStateCpp::get_fullmove_number);
	ClassDB::bind_method(D_METHOD("set_fullmove_number", "value"), &XiangqiNativeStateCpp::set_fullmove_number);
	ClassDB::bind_method(D_METHOD("has_piece_at", "index"), &XiangqiNativeStateCpp::has_piece_at);
	ClassDB::bind_method(D_METHOD("is_empty_at", "index"), &XiangqiNativeStateCpp::is_empty_at);
	ClassDB::bind_method(D_METHOD("get_piece_at", "index"), &XiangqiNativeStateCpp::get_piece_at);
	ClassDB::bind_method(D_METHOD("set_piece_at", "index", "piece_text"), &XiangqiNativeStateCpp::set_piece_at);
	ClassDB::bind_method(D_METHOD("remove_piece_at", "index"), &XiangqiNativeStateCpp::remove_piece_at);
	ClassDB::bind_method(D_METHOD("apply_move", "from_index", "to_index", "piece_text", "flags"), &XiangqiNativeStateCpp::apply_move);
	ClassDB::bind_method(D_METHOD("undo_move", "from_index", "to_index", "piece_text", "captured_piece_text", "flags"), &XiangqiNativeStateCpp::undo_move);
	ClassDB::bind_method(D_METHOD("find_piece", "piece_text"), &XiangqiNativeStateCpp::find_piece);
	ClassDB::bind_method(D_METHOD("find_general", "side"), &XiangqiNativeStateCpp::find_general);
	ClassDB::bind_method(D_METHOD("get_piece_side", "index"), &XiangqiNativeStateCpp::get_piece_side);
	ClassDB::bind_method(D_METHOD("get_indices_for_side", "side"), &XiangqiNativeStateCpp::get_indices_for_side);
	ClassDB::bind_method(D_METHOD("get_piece_count"), &XiangqiNativeStateCpp::get_piece_count);
	ClassDB::bind_method(D_METHOD("duplicate_state"), &XiangqiNativeStateCpp::duplicate_state);
}
