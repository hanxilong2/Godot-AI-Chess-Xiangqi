extends Node3D
class_name StateMachine

signal state_changed(state:String)
const DEBUG_STATE_CHANGES:bool = false

var current_state:String = ""
var last_state:String = ""
var state_list:Dictionary = {}
var connection_list:Array = []
var mutex:Mutex = Mutex.new()

func _exit_tree() -> void:
	for connection:Dictionary in connection_list:
		var signal_obj:Object = connection["signal"].get_object()
		var method:Callable = connection["method"]
		if !is_instance_valid(signal_obj):
			continue
		if method.is_null() || !method.is_valid():
			continue
		if connection["signal"].is_connected(method):
			connection["signal"].disconnect(method)
	connection_list.clear()
	state_list.clear()
	mutex = null

func add_state(new_state:String, ready_callback:Callable = Callable(), exit_callback:Callable = Callable(), process_callback:Callable = Callable()) -> void:
	state_list[new_state] = {
		"ready": ready_callback,
		"exit": exit_callback,
		"process": process_callback,
	}

func process(_delta:float) -> void:
	if state_list.has(current_state) && state_list[current_state]["process"].is_valid():
		state_list[current_state]["process"].call(_delta)

func change_state(next_state:String, arg:Dictionary = {}) -> void:
	mutex.lock()
	for connection:Dictionary in connection_list:
		var signal_obj:Object = connection["signal"].get_object()
		var method:Callable = connection["method"]
		if !is_instance_valid(signal_obj):
			continue
		if method.is_null() || !method.is_valid():
			continue
		if connection["signal"].is_connected(method):
			connection["signal"].disconnect(method)
	connection_list.clear()
	last_state = current_state
	current_state = next_state
	if DEBUG_STATE_CHANGES:
		print(name + ":" + current_state)
	if last_state && state_list.has(last_state) && state_list[last_state]["exit"].is_valid():
		state_list[last_state]["exit"].call()
	set_physics_process(state_list.has(current_state) && state_list[current_state]["process"].is_valid())
	mutex.unlock()
	if !state_list.has(current_state):
		push_warning("State '%s' not found." % current_state)
		return
	var ready_callback:Callable = state_list[current_state]["ready"]
	if ready_callback.is_valid():
		ready_callback.call(arg)
	state_changed.emit(current_state)

func state_signal_connect(_signal:Signal, _method:Callable) -> void:
	if _signal.is_null() || _method.is_null():
		return
	if !_signal.is_connected(_method):
		_signal.connect(_method)
	assert(_signal.is_connected(_method))
	connection_list.push_back({"signal": _signal, "method": _method})
