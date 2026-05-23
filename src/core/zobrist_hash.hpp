#ifndef _ZOBRIST_HASH_HPP_
#define _ZOBRIST_HASH_HPP_

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/godot.hpp>

class ZobristHash : public godot::Object
{
	GDCLASS(ZobristHash, Object)
public:
	ZobristHash();
	static ZobristHash *get_singleton();
	static void destroy_singleton();
	int64_t hash_piece(int _piece, int _by);
	void print_randomized();
	static void _bind_methods();

private:
	static ZobristHash *singleton;
	int64_t randomized[65536];
};

#endif
