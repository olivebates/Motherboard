extends Node

var count = 0
signal count_changed(new_count: int)

func add_orb() -> void:
	count += 1
	count_changed.emit(count)
