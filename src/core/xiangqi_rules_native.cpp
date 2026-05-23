#include "xiangqi_rules_native.hpp"

#include <algorithm>
#include <cctype>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>

using namespace godot;

namespace
{
constexpr XiangqiRulesNativeCpp::Direction ORTHOGONAL_DIRECTIONS[] = {
	{1, 0},
	{-1, 0},
	{0, 1},
	{0, -1},
};

constexpr XiangqiRulesNativeCpp::Direction ADVISOR_DIRECTIONS[] = {
	{1, 1},
	{1, -1},
	{-1, 1},
	{-1, -1},
};

constexpr XiangqiRulesNativeCpp::StepPattern ELEPHANT_PATTERNS[] = {
	{2, 2, 1, 1},
	{2, -2, 1, -1},
	{-2, 2, -1, 1},
	{-2, -2, -1, -1},
};

constexpr XiangqiRulesNativeCpp::StepPattern HORSE_PATTERNS[] = {
	{1, 2, 0, 1},
	{-1, 2, 0, 1},
	{1, -2, 0, -1},
	{-1, -2, 0, -1},
	{2, 1, 1, 0},
	{2, -1, 1, 0},
	{-2, 1, -1, 0},
	{-2, -1, -1, 0},
};

} // namespace

int XiangqiRulesNativeCpp::implementation_stage() const
{
	return 3;
}

bool XiangqiRulesNativeCpp::rules_ready() const
{
	return true;
}

PackedInt32Array XiangqiRulesNativeCpp::generate_pseudo_legal_moves(Object *state, int from_index) const
{
	Position position;
	if (!try_read_state(state, position))
	{
		return PackedInt32Array();
	}
	return encode_moves(generate_pseudo_legal_moves_for_board(position.board, position.side_to_move, from_index));
}

PackedInt32Array XiangqiRulesNativeCpp::generate_pseudo_legal_moves_for_side(Object *state, int side, int from_index) const
{
	Position position;
	if (!try_read_state(state, position))
	{
		return PackedInt32Array();
	}
	return encode_moves(generate_pseudo_legal_moves_for_board(position.board, side, from_index));
}

PackedInt32Array XiangqiRulesNativeCpp::generate_legal_moves(Object *state, int side, int from_index) const
{
	Position position;
	if (!try_read_state(state, position))
	{
		return PackedInt32Array();
	}

	const int resolved_side = resolve_side(position, side);
	return encode_moves(generate_legal_moves_for_board(position.board, resolved_side, from_index, true));
}

bool XiangqiRulesNativeCpp::is_legal_move(Object *state, Object *move, int side) const
{
	Position position;
	int from_index = -1;
	int to_index = -1;
	if (!try_read_state(state, position) || !try_read_move(move, from_index, to_index))
	{
		return false;
	}

	const int resolved_side = resolve_side(position, side);
	if (!owns_piece(position.board, from_index, resolved_side))
	{
		return false;
	}

	const std::vector<MoveData> candidates = generate_pseudo_legal_moves_for_board(position.board, resolved_side, from_index);
	for (const MoveData &candidate : candidates)
	{
		if (candidate.from != from_index || candidate.to != to_index)
		{
			continue;
		}

		if (is_move_legal_on_board(position.board, candidate, resolved_side))
		{
			return true;
		}
	}
	return false;
}

bool XiangqiRulesNativeCpp::is_in_check(Object *state, int side) const
{
	Position position;
	if (!try_read_state(state, position))
	{
		return false;
	}
	return is_in_check_on_board(position.board, side);
}

bool XiangqiRulesNativeCpp::are_generals_facing(Object *state) const
{
	Position position;
	if (!try_read_state(state, position))
	{
		return false;
	}
	return are_generals_facing_on_board(position.board);
}

bool XiangqiRulesNativeCpp::has_any_legal_move(Object *state, int side, int from_index) const
{
	Position position;
	if (!try_read_state(state, position))
	{
		return false;
	}
	return has_any_legal_move_on_board(position.board, resolve_side(position, side), from_index);
}

bool XiangqiRulesNativeCpp::is_checkmate(Object *state, int side) const
{
	Position position;
	if (!try_read_state(state, position))
	{
		return false;
	}

	const int resolved_side = resolve_side(position, side);
	return !has_any_legal_move_on_board(position.board, resolved_side, -1);
}

bool XiangqiRulesNativeCpp::is_stalemate(Object *state, int side) const
{
	Position position;
	if (!try_read_state(state, position))
	{
		return false;
	}

	return false;
}

String XiangqiRulesNativeCpp::get_position_status(Object *state, int side) const
{
	Position position;
	if (!try_read_state(state, position))
	{
		return "invalid";
	}

	const int resolved_side = resolve_side(position, side);
	const bool in_check = is_in_check_on_board(position.board, resolved_side);
	const bool has_move = has_any_legal_move_on_board(position.board, resolved_side, -1);

	if (!has_move)
	{
		return "checkmate";
	}
	return in_check ? String("check") : String("ok");
}

bool XiangqiRulesNativeCpp::try_read_state(Object *state, Position &position)
{
	position.board.fill(EMPTY);
	position.side_to_move = RED;

	const XiangqiNativeStateCpp *native_state = Object::cast_to<XiangqiNativeStateCpp>(state);
	if (native_state != nullptr)
	{
		position.board = native_state->get_board_data();
		position.side_to_move = native_state->get_side_to_move_value();
		return true;
	}

	if (state == nullptr)
	{
		return false;
	}

	const Variant board_variant = state->get(StringName("board"));
	if (board_variant.get_type() != Variant::ARRAY)
	{
		return false;
	}

	const Array board_array = board_variant;
	if (board_array.size() < BOARD_SIZE)
	{
		return false;
	}

	for (int index = 0; index < BOARD_SIZE; index++)
	{
		const String piece_text = board_array[index];
		position.board[index] = XiangqiNativeStateCpp::normalize_piece(piece_text);
	}

	const Variant side_variant = state->get(StringName("side_to_move"));
	if (side_variant.get_type() == Variant::INT)
	{
		position.side_to_move = static_cast<int>(side_variant);
	}
	return true;
}

bool XiangqiRulesNativeCpp::try_read_move(Object *move, int &from_index, int &to_index)
{
	from_index = -1;
	to_index = -1;
	if (move == nullptr)
	{
		return false;
	}

	from_index = static_cast<int>(move->get(StringName("from_index")));
	to_index = static_cast<int>(move->get(StringName("to_index")));
	return is_valid_index(from_index) && is_valid_index(to_index);
}

PackedInt32Array XiangqiRulesNativeCpp::encode_moves(const std::vector<MoveData> &moves)
{
	PackedInt32Array encoded;
	encoded.resize(static_cast<int64_t>(moves.size()) * 5);

	int write_index = 0;
	for (const MoveData &move : moves)
	{
		encoded.set(write_index++, move.from);
		encoded.set(write_index++, move.to);
		encoded.set(write_index++, move.piece);
		encoded.set(write_index++, move.captured_piece);
		encoded.set(write_index++, move.flags);
	}
	return encoded;
}

std::vector<XiangqiRulesNativeCpp::MoveData> XiangqiRulesNativeCpp::generate_pseudo_legal_moves_for_board(const std::array<char, BOARD_SIZE> &board, int side, int from_index)
{
	std::vector<MoveData> moves;
	moves.reserve(96);

	if (from_index != -1)
	{
		if (owns_piece(board, from_index, side))
		{
			append_piece_moves(board, from_index, moves);
		}
		return moves;
	}

	for (int index = 0; index < BOARD_SIZE; index++)
	{
		if (owns_piece(board, index, side))
		{
			append_piece_moves(board, index, moves);
		}
	}
	return moves;
}

std::vector<XiangqiRulesNativeCpp::MoveData> XiangqiRulesNativeCpp::generate_legal_moves_for_board(std::array<char, BOARD_SIZE> &board, int side, int from_index, bool include_check_flags)
{
	std::vector<MoveData> legal_moves;
	legal_moves.reserve(96);
	const std::vector<MoveData> candidates = generate_pseudo_legal_moves_for_board(board, side, from_index);

	for (const MoveData &candidate : candidates)
	{
		if (!is_move_legal_on_board(board, candidate, side))
		{
			continue;
		}

		int flags = candidate.flags;
		if (include_check_flags)
		{
			char captured_piece = EMPTY;
			apply_move(board, candidate, captured_piece);
			const int opponent = other_side(side);
			if (is_in_check_on_board(board, opponent))
			{
				flags |= FLAG_CHECK;
			}
			if (!has_any_legal_move_on_board(board, opponent, -1))
			{
				flags |= FLAG_CHECKMATE;
			}
			undo_move(board, candidate, captured_piece);
		}

		legal_moves.push_back({candidate.from, candidate.to, candidate.piece, candidate.captured_piece, flags});
	}
	return legal_moves;
}

bool XiangqiRulesNativeCpp::has_any_legal_move_on_board(std::array<char, BOARD_SIZE> &board, int side, int from_index)
{
	const std::vector<MoveData> candidates = generate_pseudo_legal_moves_for_board(board, side, from_index);
	for (const MoveData &candidate : candidates)
	{
		if (is_move_legal_on_board(board, candidate, side))
		{
			return true;
		}
	}
	return false;
}

bool XiangqiRulesNativeCpp::is_move_legal_on_board(std::array<char, BOARD_SIZE> &board, const MoveData &move, int side)
{
	char captured_piece = EMPTY;
	apply_move(board, move, captured_piece);
	const bool legal = !are_generals_facing_on_board(board) && !is_in_check_on_board(board, side);
	undo_move(board, move, captured_piece);
	return legal;
}

void XiangqiRulesNativeCpp::apply_move(std::array<char, BOARD_SIZE> &board, const MoveData &move, char &captured_piece)
{
	captured_piece = board[move.to];
	board[move.from] = EMPTY;
	board[move.to] = move.piece;
}

void XiangqiRulesNativeCpp::undo_move(std::array<char, BOARD_SIZE> &board, const MoveData &move, char captured_piece)
{
	board[move.from] = move.piece;
	board[move.to] = captured_piece;
}

void XiangqiRulesNativeCpp::append_piece_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves)
{
	const char piece = board[from_index];
	if (piece == EMPTY)
	{
		return;
	}

	switch (piece_type(piece))
	{
		case 'r':
			generate_rook_moves(board, from_index, moves);
			break;
		case 'c':
			generate_cannon_moves(board, from_index, moves);
			break;
		case 'h':
			generate_horse_moves(board, from_index, moves);
			break;
		case 'e':
			generate_elephant_moves(board, from_index, moves);
			break;
		case 'a':
			generate_advisor_moves(board, from_index, moves);
			break;
		case 'k':
			generate_general_moves(board, from_index, moves);
			break;
		case 'p':
			generate_soldier_moves(board, from_index, moves);
			break;
		default:
			break;
	}
}

void XiangqiRulesNativeCpp::generate_rook_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves)
{
	const int file = file_of(from_index);
	const int rank = rank_of(from_index);

	for (const Direction &direction : ORTHOGONAL_DIRECTIONS)
	{
		int next_file = file + direction.file;
		int next_rank = rank + direction.rank;
		while (is_valid(next_file, next_rank))
		{
			const int to = to_index(next_file, next_rank);
			if (board[to] == EMPTY)
			{
				append_move(board, moves, from_index, to);
			}
			else
			{
				append_move(board, moves, from_index, to);
				break;
			}

			next_file += direction.file;
			next_rank += direction.rank;
		}
	}
}

void XiangqiRulesNativeCpp::generate_cannon_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves)
{
	const int file = file_of(from_index);
	const int rank = rank_of(from_index);

	for (const Direction &direction : ORTHOGONAL_DIRECTIONS)
	{
		int next_file = file + direction.file;
		int next_rank = rank + direction.rank;
		bool screen_found = false;

		while (is_valid(next_file, next_rank))
		{
			const int to = to_index(next_file, next_rank);
			if (!screen_found)
			{
				if (board[to] == EMPTY)
				{
					append_move(board, moves, from_index, to);
				}
				else
				{
					screen_found = true;
				}
			}
			else if (board[to] != EMPTY)
			{
				append_move(board, moves, from_index, to);
				break;
			}

			next_file += direction.file;
			next_rank += direction.rank;
		}
	}
}

void XiangqiRulesNativeCpp::generate_horse_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves)
{
	const int file = file_of(from_index);
	const int rank = rank_of(from_index);

	for (const StepPattern &pattern : HORSE_PATTERNS)
	{
		const int leg_file = file + pattern.block_file;
		const int leg_rank = rank + pattern.block_rank;
		if (!is_valid(leg_file, leg_rank) || board[to_index(leg_file, leg_rank)] != EMPTY)
		{
			continue;
		}

		const int target_file = file + pattern.move_file;
		const int target_rank = rank + pattern.move_rank;
		if (is_valid(target_file, target_rank))
		{
			append_move(board, moves, from_index, to_index(target_file, target_rank));
		}
	}
}

void XiangqiRulesNativeCpp::generate_elephant_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves)
{
	const int side = side_from_piece(board[from_index]);
	const int file = file_of(from_index);
	const int rank = rank_of(from_index);

	for (const StepPattern &pattern : ELEPHANT_PATTERNS)
	{
		const int eye_file = file + pattern.block_file;
		const int eye_rank = rank + pattern.block_rank;
		if (!is_valid(eye_file, eye_rank) || board[to_index(eye_file, eye_rank)] != EMPTY)
		{
			continue;
		}

		const int target_file = file + pattern.move_file;
		const int target_rank = rank + pattern.move_rank;
		if (!is_valid(target_file, target_rank) || has_crossed_river(side, target_rank))
		{
			continue;
		}

		append_move(board, moves, from_index, to_index(target_file, target_rank));
	}
}

void XiangqiRulesNativeCpp::generate_advisor_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves)
{
	const int side = side_from_piece(board[from_index]);
	const int file = file_of(from_index);
	const int rank = rank_of(from_index);

	for (const Direction &direction : ADVISOR_DIRECTIONS)
	{
		const int target_file = file + direction.file;
		const int target_rank = rank + direction.rank;
		if (is_valid(target_file, target_rank) && is_in_palace(side, target_file, target_rank))
		{
			append_move(board, moves, from_index, to_index(target_file, target_rank));
		}
	}
}

void XiangqiRulesNativeCpp::generate_general_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves)
{
	const int side = side_from_piece(board[from_index]);
	const int file = file_of(from_index);
	const int rank = rank_of(from_index);

	for (const Direction &direction : ORTHOGONAL_DIRECTIONS)
	{
		const int target_file = file + direction.file;
		const int target_rank = rank + direction.rank;
		if (is_valid(target_file, target_rank) && is_in_palace(side, target_file, target_rank))
		{
			append_move(board, moves, from_index, to_index(target_file, target_rank));
		}
	}

	const int enemy_general_index = find_general(board, other_side(side));
	if (enemy_general_index == -1 || file_of(enemy_general_index) != file)
	{
		return;
	}

	if (count_pieces_between_on_file(board, file, rank, rank_of(enemy_general_index)) == 0)
	{
		append_move(board, moves, from_index, enemy_general_index, FLAG_SPECIAL);
	}
}

void XiangqiRulesNativeCpp::generate_soldier_moves(const std::array<char, BOARD_SIZE> &board, int from_index, std::vector<MoveData> &moves)
{
	const int side = side_from_piece(board[from_index]);
	const int file = file_of(from_index);
	const int rank = rank_of(from_index);
	const int forward = side == RED ? -1 : 1;
	const int forward_rank = rank + forward;

	if (is_valid(file, forward_rank))
	{
		append_move(board, moves, from_index, to_index(file, forward_rank));
	}

	if (!has_crossed_river(side, rank))
	{
		return;
	}

	const int left_file = file - 1;
	const int right_file = file + 1;
	if (is_valid(left_file, rank))
	{
		append_move(board, moves, from_index, to_index(left_file, rank));
	}
	if (is_valid(right_file, rank))
	{
		append_move(board, moves, from_index, to_index(right_file, rank));
	}
}

void XiangqiRulesNativeCpp::append_move(const std::array<char, BOARD_SIZE> &board, std::vector<MoveData> &moves, int from_index, int to, int extra_flags)
{
	if (!is_valid_index(from_index) || !is_valid_index(to))
	{
		return;
	}

	const char piece = board[from_index];
	if (piece == EMPTY)
	{
		return;
	}

	const char captured_piece = board[to];
	if (captured_piece != EMPTY && side_from_piece(captured_piece) == side_from_piece(piece))
	{
		return;
	}

	int flags = extra_flags;
	if (captured_piece != EMPTY)
	{
		flags |= FLAG_CAPTURE;
	}

	moves.push_back({from_index, to, piece, captured_piece, flags});
}

bool XiangqiRulesNativeCpp::is_in_check_on_board(const std::array<char, BOARD_SIZE> &board, int side)
{
	const int general_index = find_general(board, side);
	if (general_index == -1)
	{
		return true;
	}
	return is_square_attacked(board, general_index, other_side(side));
}

bool XiangqiRulesNativeCpp::is_square_attacked(const std::array<char, BOARD_SIZE> &board, int square_index, int attacker_side)
{
	const int file = file_of(square_index);
	const int rank = rank_of(square_index);

	if (is_attacked_by_rook_cannon_or_general(board, file, rank, attacker_side))
	{
		return true;
	}
	if (is_attacked_by_horse(board, file, rank, attacker_side))
	{
		return true;
	}
	if (is_attacked_by_soldier(board, file, rank, attacker_side))
	{
		return true;
	}
	if (is_attacked_by_advisor(board, file, rank, attacker_side))
	{
		return true;
	}
	return is_attacked_by_elephant(board, file, rank, attacker_side);
}

bool XiangqiRulesNativeCpp::is_attacked_by_rook_cannon_or_general(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side)
{
	for (const Direction &direction : ORTHOGONAL_DIRECTIONS)
	{
		int next_file = file + direction.file;
		int next_rank = rank + direction.rank;
		bool screen_found = false;

		while (is_valid(next_file, next_rank))
		{
			const int index = to_index(next_file, next_rank);
			const char piece = board[index];
			if (piece == EMPTY)
			{
				next_file += direction.file;
				next_rank += direction.rank;
				continue;
			}

			if (!screen_found)
			{
				if (side_from_piece(piece) == attacker_side)
				{
					const char type = piece_type(piece);
					if (type == 'r')
					{
						return true;
					}
					if (type == 'k' && direction.file == 0)
					{
						return true;
					}
				}

				screen_found = true;
				next_file += direction.file;
				next_rank += direction.rank;
				continue;
			}

			if (side_from_piece(piece) == attacker_side && piece_type(piece) == 'c')
			{
				return true;
			}
			break;
		}
	}
	return false;
}

bool XiangqiRulesNativeCpp::is_attacked_by_horse(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side)
{
	for (const StepPattern &pattern : HORSE_PATTERNS)
	{
		const int attacker_file = file - pattern.move_file;
		const int attacker_rank = rank - pattern.move_rank;
		const int leg_file = attacker_file + pattern.block_file;
		const int leg_rank = attacker_rank + pattern.block_rank;

		if (!is_valid(attacker_file, attacker_rank) || !is_valid(leg_file, leg_rank))
		{
			continue;
		}
		if (board[to_index(leg_file, leg_rank)] != EMPTY)
		{
			continue;
		}

		const char piece = board[to_index(attacker_file, attacker_rank)];
		if (piece != EMPTY && side_from_piece(piece) == attacker_side && piece_type(piece) == 'h')
		{
			return true;
		}
	}
	return false;
}

bool XiangqiRulesNativeCpp::is_attacked_by_soldier(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side)
{
	const int forward_source_rank = attacker_side == RED ? rank + 1 : rank - 1;
	if (is_valid(file, forward_source_rank))
	{
		const char piece = board[to_index(file, forward_source_rank)];
		if (piece != EMPTY && side_from_piece(piece) == attacker_side && piece_type(piece) == 'p')
		{
			return true;
		}
	}

	const int left_file = file - 1;
	if (is_valid(left_file, rank) && is_crossed_soldier(board, left_file, rank, attacker_side))
	{
		return true;
	}

	const int right_file = file + 1;
	return is_valid(right_file, rank) && is_crossed_soldier(board, right_file, rank, attacker_side);
}

bool XiangqiRulesNativeCpp::is_crossed_soldier(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side)
{
	const char piece = board[to_index(file, rank)];
	return piece != EMPTY &&
		side_from_piece(piece) == attacker_side &&
		piece_type(piece) == 'p' &&
		has_crossed_river(attacker_side, rank);
}

bool XiangqiRulesNativeCpp::is_attacked_by_advisor(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side)
{
	for (const Direction &direction : ADVISOR_DIRECTIONS)
	{
		const int attacker_file = file - direction.file;
		const int attacker_rank = rank - direction.rank;
		if (!is_valid(attacker_file, attacker_rank) || !is_in_palace(attacker_side, attacker_file, attacker_rank))
		{
			continue;
		}

		const char piece = board[to_index(attacker_file, attacker_rank)];
		if (piece != EMPTY && side_from_piece(piece) == attacker_side && piece_type(piece) == 'a')
		{
			return true;
		}
	}
	return false;
}

bool XiangqiRulesNativeCpp::is_attacked_by_elephant(const std::array<char, BOARD_SIZE> &board, int file, int rank, int attacker_side)
{
	for (const StepPattern &pattern : ELEPHANT_PATTERNS)
	{
		const int attacker_file = file - pattern.move_file;
		const int attacker_rank = rank - pattern.move_rank;
		const int eye_file = attacker_file + pattern.block_file;
		const int eye_rank = attacker_rank + pattern.block_rank;

		if (!is_valid(attacker_file, attacker_rank) || !is_valid(eye_file, eye_rank))
		{
			continue;
		}
		if (board[to_index(eye_file, eye_rank)] != EMPTY || has_crossed_river(attacker_side, rank))
		{
			continue;
		}

		const char piece = board[to_index(attacker_file, attacker_rank)];
		if (piece != EMPTY && side_from_piece(piece) == attacker_side && piece_type(piece) == 'e')
		{
			return true;
		}
	}
	return false;
}

bool XiangqiRulesNativeCpp::are_generals_facing_on_board(const std::array<char, BOARD_SIZE> &board)
{
	const int red_general = find_general(board, RED);
	const int black_general = find_general(board, BLACK);
	if (red_general == -1 || black_general == -1 || file_of(red_general) != file_of(black_general))
	{
		return false;
	}
	return count_pieces_between_on_file(board, file_of(red_general), rank_of(red_general), rank_of(black_general)) == 0;
}

int XiangqiRulesNativeCpp::count_pieces_between_on_file(const std::array<char, BOARD_SIZE> &board, int file, int rank_a, int rank_b)
{
	if (rank_a == rank_b)
	{
		return 0;
	}

	int count = 0;
	const int start_rank = std::min(rank_a, rank_b) + 1;
	const int end_rank = std::max(rank_a, rank_b);
	for (int rank = start_rank; rank < end_rank; rank++)
	{
		if (board[to_index(file, rank)] != EMPTY)
		{
			count++;
		}
	}
	return count;
}

int XiangqiRulesNativeCpp::find_general(const std::array<char, BOARD_SIZE> &board, int side)
{
	const char general = side == RED ? 'K' : 'k';
	for (int index = 0; index < BOARD_SIZE; index++)
	{
		if (board[index] == general)
		{
			return index;
		}
	}
	return -1;
}

bool XiangqiRulesNativeCpp::owns_piece(const std::array<char, BOARD_SIZE> &board, int index, int side)
{
	return is_valid_index(index) && board[index] != EMPTY && side_from_piece(board[index]) == side;
}

int XiangqiRulesNativeCpp::resolve_side(const Position &position, int side)
{
	return side == -1 ? position.side_to_move : side;
}

int XiangqiRulesNativeCpp::other_side(int side)
{
	return side == RED ? BLACK : RED;
}

int XiangqiRulesNativeCpp::side_from_piece(char piece)
{
	return std::isupper(static_cast<unsigned char>(piece)) ? RED : BLACK;
}

char XiangqiRulesNativeCpp::piece_type(char piece)
{
	return static_cast<char>(std::tolower(static_cast<unsigned char>(piece)));
}

bool XiangqiRulesNativeCpp::has_crossed_river(int side, int rank)
{
	return side == RED ? rank <= 4 : rank >= 5;
}

bool XiangqiRulesNativeCpp::is_in_palace(int side, int file, int rank)
{
	if (file < 3 || file > 5)
	{
		return false;
	}
	return side == RED ? rank >= 7 && rank <= 9 : rank >= 0 && rank <= 2;
}

bool XiangqiRulesNativeCpp::is_valid(int file, int rank)
{
	return file >= 0 && file < BOARD_FILES && rank >= 0 && rank < BOARD_RANKS;
}

bool XiangqiRulesNativeCpp::is_valid_index(int index)
{
	return index >= 0 && index < BOARD_SIZE;
}

int XiangqiRulesNativeCpp::to_index(int file, int rank)
{
	return rank * BOARD_FILES + file;
}

int XiangqiRulesNativeCpp::file_of(int index)
{
	return index % BOARD_FILES;
}

int XiangqiRulesNativeCpp::rank_of(int index)
{
	return index / BOARD_FILES;
}

void XiangqiRulesNativeCpp::_bind_methods()
{
	ClassDB::bind_method(D_METHOD("implementation_stage"), &XiangqiRulesNativeCpp::implementation_stage);
	ClassDB::bind_method(D_METHOD("rules_ready"), &XiangqiRulesNativeCpp::rules_ready);
	ClassDB::bind_method(D_METHOD("generate_pseudo_legal_moves", "state", "from_index"), &XiangqiRulesNativeCpp::generate_pseudo_legal_moves);
	ClassDB::bind_method(D_METHOD("generate_pseudo_legal_moves_for_side", "state", "side", "from_index"), &XiangqiRulesNativeCpp::generate_pseudo_legal_moves_for_side);
	ClassDB::bind_method(D_METHOD("generate_legal_moves", "state", "side", "from_index"), &XiangqiRulesNativeCpp::generate_legal_moves);
	ClassDB::bind_method(D_METHOD("is_legal_move", "state", "move", "side"), &XiangqiRulesNativeCpp::is_legal_move);
	ClassDB::bind_method(D_METHOD("is_in_check", "state", "side"), &XiangqiRulesNativeCpp::is_in_check);
	ClassDB::bind_method(D_METHOD("are_generals_facing", "state"), &XiangqiRulesNativeCpp::are_generals_facing);
	ClassDB::bind_method(D_METHOD("has_any_legal_move", "state", "side", "from_index"), &XiangqiRulesNativeCpp::has_any_legal_move);
	ClassDB::bind_method(D_METHOD("is_checkmate", "state", "side"), &XiangqiRulesNativeCpp::is_checkmate);
	ClassDB::bind_method(D_METHOD("is_stalemate", "state", "side"), &XiangqiRulesNativeCpp::is_stalemate);
	ClassDB::bind_method(D_METHOD("get_position_status", "state", "side"), &XiangqiRulesNativeCpp::get_position_status);
}
