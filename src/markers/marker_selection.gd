@abstract
extends Node3D
class_name MarkerSelection

@onready var level:Level = get_parent()
@export var selection:String = ""
@export_custom(PropertyHint.PROPERTY_HINT_FLAGS, "bitboard") var bit:int = 0

@abstract func event() -> void
