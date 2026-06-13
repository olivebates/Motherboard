extends TileMapLayer

func _ready() -> void:
	if tile_set != null:
		return
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	var source := TileSetAtlasSource.new()
	source.texture = load("res://Sprites/objects/placeholder.png")
	source.texture_region_size = Vector2i(32, 32)
	source.create_tile(Vector2i(0, 0))
	ts.add_source(source, 0)
	tile_set = ts
	modulate = Color(0.35, 0.35, 0.4)
