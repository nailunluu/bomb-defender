extends Node2D
## BOMB DEFENDER - Godot 4.x, no paid assets, no API key.

const W: int = 17
const H: int = 13
const TILE: int = 44
const BOARD: Vector2 = Vector2(62, 132)
const BG: Color = Color("0b1020")
const PANEL: Color = Color("111a2e")
const LINE: Color = Color("243652")
const TEXT: Color = Color("edf4ff")
const MUTED: Color = Color("92a5c0")
const CYAN: Color = Color("49ddf3")
const GOLD: Color = Color("ffca66")
const PINK: Color = Color("ff6392")
const FLOOR: int = 0
const HARD: int = 1
const SOFT: int = 2
const PU_RANGE: int = 0
const PU_CAPACITY: int = 1
const PU_SPEED: int = 2
const PU_HEART: int = 3
const PU_REMOTE: int = 4 # D: remote detonation. One-time ability.
const PU_KICK: int = 5 # K: kick a bomb to slide it until an obstacle.
const PU_CRATE_PASS: int = 6 # G: walk THROUGH breakable crates.
const BOMB_SLIDE_INTERVAL: float = 0.115
# Flame visuals and damage share one timer: no invisible lingering hitbox.
const FLAME_DURATION: float = 0.26
# Monsters actively investigate bombs instead of avoiding their whole blast lane.
# They cannot step onto the solid bomb tile, but can move right next to it.
const ENEMY_BOMB_CHASE_CHANCE: float = 0.90
const ENEMY_TIMED_BOMB_WAIT_CHANCE: float = 0.76
const ENEMY_REMOTE_BOMB_WAIT_CHANCE: float = 0.42
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var grid: Array = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var player_cell: Vector2i = Vector2i(1, 1)
var player_visual: Vector2 = Vector2(1, 1)
var player_move_cooldown: float = 0.0
var invulnerable: float = 0.0
var enemies: Array[Dictionary] = []
var bombs: Array[Dictionary] = []
var flames: Array[Dictionary] = []
var game_state: String = "menu"
var level: int = 1
var lives: int = 3
var score: int = 0
var best_score: int = 0
var blast_range: int = 1
var max_bombs: int = 1
var speed_upgrade: int = 0
var remote_unlocked: bool = false
var kick_unlocked: bool = false
var crate_pass_unlocked: bool = false
# One and only one reward is picked for each level, BEFORE its crate is opened.
# The weighted draw makes special abilities uncommon but possible on any level.
# When a permanent ability is already unlocked it is removed from this draw.
# Every arena hides exactly one randomly chosen upgrade in a single breakable crate.
# The crate first reveals a collectible icon, which must be picked up on foot.
var hidden_reward_cell: Vector2i = Vector2i(-1, -1)
var dropped_reward_cell: Vector2i = Vector2i(-1, -1)
var chosen_reward_kind: int = -1
var reward_revealed: bool = false
var reward_claimed: bool = false
# One other randomly selected crate contains the level's EXIT door.
# The door is revealed by an explosion and opens only after all opponents
# are defeated and the single collectible reward has been picked up.
var hidden_exit_cell: Vector2i = Vector2i(-1, -1)
var revealed_exit_cell: Vector2i = Vector2i(-1, -1)
var exit_revealed: bool = false
var level_transition_time: float = 0.0
var reward_toast_time: float = 0.0
var last_reward_kind: int = -1
var last_reward_name: String = ""
var last_reward_detail: String = ""
const MAX_RANGE: int = 6
const MAX_BOMBS: int = 5
const MAX_SPEED: int = 3
const MAX_LIVES: int = 5
var countdown: float = 180.0
var elapsed: float = 0.0
var sounds: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	_load_best_score()
	_setup_sounds()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		if key == KEY_ESCAPE or key == KEY_P:
			if game_state == "playing":
				game_state = "paused"
			elif game_state == "paused":
				game_state = "playing"
		elif key == KEY_ENTER:
			if game_state == "menu" or game_state == "game_over":
				_start_new_game()
			elif game_state == "level_clear":
				_start_next_level()
		elif key == KEY_R:
			_start_new_game()
		elif key == KEY_SPACE and game_state == "playing":
			_place_bomb()
		elif key == KEY_E and game_state == "playing":
			_manual_detonate_oldest_bomb()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var pt: Vector2 = event.position
		if game_state == "menu" or game_state == "game_over" or game_state == "level_clear":
			if Rect2(486, 478, 308, 62).has_point(pt):
				if game_state == "level_clear":
					_start_next_level()
				else:
					_start_new_game()

func _process(delta: float) -> void:
	elapsed += delta
	if game_state == "playing":
		countdown = maxf(0.0, countdown - delta)
		player_move_cooldown = maxf(0.0, player_move_cooldown - delta)
		invulnerable = maxf(0.0, invulnerable - delta)
		reward_toast_time = maxf(0.0, reward_toast_time - delta)
		# Expire old flames BEFORE input/movement and collision checks.
		# This prevents a player from taking damage from a flame that disappears
		# in the same frame, after movement but before rendering.
		_update_flames(delta)
		_handle_movement()
		_update_sliding_bombs(delta)
		_update_bombs(delta)
		_update_enemies(delta)
		_check_player_hazards()
		if countdown <= 0.0:
			_lost_game()
		if game_state == "playing" and _exit_is_open() and player_cell == revealed_exit_cell:
			_win_level()
	elif game_state == "level_clear":
		# The discovered door automatically takes the player to the next arena.
		level_transition_time = maxf(0.0, level_transition_time - delta)
		if level_transition_time <= 0.0:
			_start_next_level()
	player_visual = player_visual.lerp(Vector2(player_cell), minf(1.0, 15.0 * delta))
	for enemy in enemies:
		var enemy_pos: Vector2 = enemy["visual"]
		enemy["visual"] = enemy_pos.lerp(Vector2(enemy["cell"]), minf(1.0, delta * 10.0))
	queue_redraw()

func _start_new_game() -> void:
	level = 1
	lives = 3
	score = 0
	blast_range = 1
	max_bombs = 1
	speed_upgrade = 0
	remote_unlocked = false # Reset only on a fresh run.
	kick_unlocked = false
	crate_pass_unlocked = false
	last_reward_kind = -1
	last_reward_name = ""
	last_reward_detail = ""
	_start_next_level()

func _start_next_level() -> void:
	game_state = "playing"
	countdown = 180.0
	invulnerable = 1.3
	player_move_cooldown = 0.0
	bombs.clear()
	flames.clear()
	enemies.clear()
	hidden_reward_cell = Vector2i(-1, -1)
	dropped_reward_cell = Vector2i(-1, -1)
	chosen_reward_kind = -1
	reward_revealed = false
	reward_claimed = false
	hidden_exit_cell = Vector2i(-1, -1)
	revealed_exit_cell = Vector2i(-1, -1)
	exit_revealed = false
	level_transition_time = 0.0
	reward_toast_time = 0.0
	last_reward_kind = -1
	last_reward_name = ""
	last_reward_detail = ""
	player_cell = Vector2i(1, 1)
	player_visual = Vector2(player_cell)
	_generate_level()

func _generate_level() -> void:
	grid.clear()
	for y in range(H):
		var row: Array[int] = []
		for x in range(W):
			if x == 0 or y == 0 or x == W - 1 or y == H - 1 or (x % 2 == 0 and y % 2 == 0):
				row.append(HARD)
			elif rng.randf() < 0.47:
				row.append(SOFT)
			else:
				row.append(FLOOR)
		grid.append(row)
	# Start corridor and opponent spawn zones remain open.
	_clear_spawn_zone(Vector2i(1, 1))
	var spawns: Array[Vector2i] = [Vector2i(15, 11), Vector2i(15, 1), Vector2i(1, 11), Vector2i(13, 9), Vector2i(11, 3)]
	var count: int = mini(2 + (level - 1) / 2, spawns.size())
	for i in range(count):
		var cell: Vector2i = spawns[i]
		_clear_spawn_zone(cell)
		enemies.append({"cell": cell, "visual": Vector2(cell), "step": 0.55 + rng.randf() * 0.2, "kind": i % 2, "phase": rng.randf() * 6.0})
	_hide_reward_and_exit_in_separate_crates()

func _hide_reward_and_exit_in_separate_crates() -> void:
	var eligible_crates: Array[Vector2i] = []
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if grid[y][x] == SOFT:
				eligible_crates.append(Vector2i(x, y))
	# Always keep two separate crates, even if a random map generated none.
	if eligible_crates.size() < 2:
		var fallbacks: Array[Vector2i] = [Vector2i(3, 1), Vector2i(1, 3), Vector2i(5, 1), Vector2i(1, 5)]
		for p in fallbacks:
			if eligible_crates.size() >= 2:
				break
			if grid[p.y][p.x] != HARD and not eligible_crates.has(p):
				grid[p.y][p.x] = SOFT
				eligible_crates.append(p)
	# Remove the selected reward crate so the door can never be inside it.
	var reward_index: int = rng.randi_range(0, eligible_crates.size() - 1)
	hidden_reward_cell = eligible_crates[reward_index]
	eligible_crates.remove_at(reward_index)
	hidden_exit_cell = eligible_crates[rng.randi_range(0, eligible_crates.size() - 1)]
	chosen_reward_kind = _choose_eligible_reward_kind()

func _exit_is_open() -> bool:
	return exit_revealed and reward_claimed and enemies.is_empty()

func _choose_eligible_reward_kind() -> int:
	# At generation time, draw ONLY ONE reward for ONLY ONE breakable crate.
	# Initial weights: D 20%, K 15%, G 15%, the four normal rewards total 50%.
	# Weights re-normalize naturally when upgrades reach their limits.
	var choices: Array[Dictionary] = []
	if blast_range < MAX_RANGE:
		choices.append({"kind": PU_RANGE, "weight": 13})
	if max_bombs < MAX_BOMBS:
		choices.append({"kind": PU_CAPACITY, "weight": 13})
	if speed_upgrade < MAX_SPEED:
		choices.append({"kind": PU_SPEED, "weight": 12})
	if lives < MAX_LIVES:
		choices.append({"kind": PU_HEART, "weight": 12})
	if not remote_unlocked:
		choices.append({"kind": PU_REMOTE, "weight": 20})
	if not kick_unlocked:
		choices.append({"kind": PU_KICK, "weight": 15})
	if not crate_pass_unlocked:
		choices.append({"kind": PU_CRATE_PASS, "weight": 15})
	if choices.is_empty():
		return -1 # All rewards maxed: the one crate gives 250 score points.
	var total_weight: int = 0
	for option in choices:
		total_weight += int(option["weight"])
	var roll: int = rng.randi_range(1, total_weight)
	for option in choices:
		roll -= int(option["weight"])
		if roll <= 0:
			return int(option["kind"])
	return int(choices[choices.size() - 1]["kind"])

func _clear_spawn_zone(center: Vector2i) -> void:
	var safe: Array[Vector2i] = [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for d in safe:
		var p: Vector2i = center + d
		if _inside(p) and grid[p.y][p.x] != HARD:
			grid[p.y][p.x] = FLOOR

func _handle_movement() -> void:
	if player_move_cooldown > 0.0:
		return
	var direction: Vector2i = Vector2i.ZERO
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		direction = Vector2i.UP
	elif Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		direction = Vector2i.DOWN
	elif Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		direction = Vector2i.LEFT
	elif Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		direction = Vector2i.RIGHT
	if direction == Vector2i.ZERO:
		return
	var target: Vector2i = player_cell + direction
	var can_step: bool = _can_walk(target, crate_pass_unlocked)
	# With K, walking toward a bomb KICKS it one square immediately;
	# the bomb then slides by itself until blocked by a wall/crate/bomb.
	if not can_step and kick_unlocked and _bomb_index_at(target) >= 0:
		can_step = _kick_bomb(target, direction)
	if can_step:
		player_cell = target
		player_move_cooldown = maxf(0.075, 0.15 - float(speed_upgrade) * 0.025)
		_check_player_hazards()
		if game_state == "playing":
			_try_collect_revealed_reward()
	else:
		player_move_cooldown = 0.065

func _inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < W and p.y < H

func _can_walk(p: Vector2i, may_pass_crate: bool = false) -> bool:
	if not _inside(p) or grid[p.y][p.x] == HARD:
		return false
	if grid[p.y][p.x] == SOFT and not may_pass_crate:
		return false
	for bomb in bombs:
		if bomb["cell"] == p:
			return false
	return true

func _bomb_index_at(p: Vector2i) -> int:
	for i in range(bombs.size()):
		if bombs[i]["cell"] == p:
			return i
	return -1

func _can_bomb_slide_into(p: Vector2i) -> bool:
	# The sliding bomb cannot pass solid walls, crates, other bombs,
	# the hero, or enemies. Wall-pass does NOT apply to bombs.
	if not _inside(p) or grid[p.y][p.x] != FLOOR:
		return false
	if _bomb_index_at(p) >= 0 or p == player_cell:
		return false
	for bot in enemies:
		if bot["cell"] == p:
			return false
	return true

func _kick_bomb(at: Vector2i, direction: Vector2i) -> bool:
	var index: int = _bomb_index_at(at)
	if index < 0 or not _can_bomb_slide_into(at + direction):
		return false
	# Move the bomb off its original square, so the hero may step onto it.
	bombs[index]["cell"] = at + direction
	bombs[index]["slide_dir"] = direction
	bombs[index]["slide_timer"] = BOMB_SLIDE_INTERVAL
	if _cell_is_burning(at + direction):
		bombs[index]["chain_triggered"] = true
	return true

func _update_sliding_bombs(delta: float) -> void:
	for bomb in bombs:
		var direction: Vector2i = bomb["slide_dir"]
		if direction == Vector2i.ZERO or bool(bomb["chain_triggered"]):
			continue
		bomb["slide_timer"] = float(bomb["slide_timer"]) - delta
		if float(bomb["slide_timer"]) > 0.0:
			continue
		var destination: Vector2i = bomb["cell"] + direction
		if not _can_bomb_slide_into(destination):
			bomb["slide_dir"] = Vector2i.ZERO
			continue
		bomb["cell"] = destination
		bomb["slide_timer"] = BOMB_SLIDE_INTERVAL
		if _cell_is_burning(destination):
			bomb["chain_triggered"] = true
			bomb["slide_dir"] = Vector2i.ZERO

func _place_bomb() -> void:
	if bombs.size() >= max_bombs or game_state != "playing":
		return
	# Crate-pass lets you WALK THROUGH a crate, not place a bomb inside it.
	if grid[player_cell.y][player_cell.x] != FLOOR:
		return
	for bomb in bombs:
		if bomb["cell"] == player_cell:
			return
	# Remote mode is stored PER bomb: bombs laid before unlocking it
	# keep their original timed fuse. The remote ones never time out.
	bombs.append({"cell": player_cell, "fuse": 2.15, "range": blast_range,
		"remote": remote_unlocked, "chain_triggered": false,
		"slide_dir": Vector2i.ZERO, "slide_timer": 0.0})
	_play_sound("place")

func _manual_detonate_oldest_bomb() -> void:
	if not remote_unlocked or game_state != "playing":
		return
	# E detonates only the oldest remote bomb. Press it again for the next.
	# An explosion can still trigger nearby bombs through chain reaction.
	for i in range(bombs.size()):
		if bool(bombs[i]["remote"]):
			_detonate(i)
			return

func _update_bombs(delta: float) -> void:
	for i in range(bombs.size() - 1, -1, -1):
		var bomb: Dictionary = bombs[i]
		# A flame can trigger a remote bomb despite its unlimited fuse.
		if bool(bomb["chain_triggered"]):
			_detonate(i)
		elif not bool(bomb["remote"]):
			bomb["fuse"] = float(bomb["fuse"]) - delta
			if float(bomb["fuse"]) <= 0.0:
				_detonate(i)

func _detonate(index: int) -> void:
	if index >= bombs.size():
		return
	var bomb: Dictionary = bombs[index]
	bombs.remove_at(index)
	_play_sound("explode")
	_blast_cell(bomb["cell"])
	for direction in DIRECTIONS:
		for distance in range(1, int(bomb["range"]) + 1):
			var source: Vector2i = bomb["cell"]
			var p: Vector2i = source + direction * distance
			if not _inside(p) or grid[p.y][p.x] == HARD:
				break
			var hits_crate: bool = grid[p.y][p.x] == SOFT
			_blast_cell(p)
			if hits_crate:
				break

func _blast_cell(p: Vector2i) -> void:
	flames.append({"cell": p, "ttl": FLAME_DURATION})
	for bomb in bombs:
		if bomb["cell"] == p:
			bomb["chain_triggered"] = true
	if grid[p.y][p.x] == SOFT:
		grid[p.y][p.x] = FLOOR
		score += 15
		# Only the one predetermined crate drops a collectible upgrade.
		if p == hidden_reward_cell and not reward_revealed:
			reward_revealed = true
			dropped_reward_cell = p
		elif p == hidden_exit_cell and not exit_revealed:
			exit_revealed = true
			revealed_exit_cell = p
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i]["cell"] == p:
			enemies.remove_at(i)
			score += 150
	if player_cell == p:
		_hurt_player()

func _update_flames(delta: float) -> void:
	for i in range(flames.size() - 1, -1, -1):
		flames[i]["ttl"] = float(flames[i]["ttl"]) - delta
		if float(flames[i]["ttl"]) <= 0.0:
			flames.remove_at(i)

func _update_enemies(delta: float) -> void:
	for i in range(enemies.size()):
		if game_state != "playing":
			return
		var bot: Dictionary = enemies[i]
		bot["step"] = float(bot["step"]) - delta
		if float(bot["step"]) > 0.0:
			continue
		bot["step"] = maxf(0.22, 0.51 - level * 0.018) + rng.randf() * 0.16
		var origin: Vector2i = bot["cell"]

		# Ninety percent of decisions while a bomb exists aim toward a free
		# neighbouring cell. Bombs are tempting targets, not hazards to flee.
		# An active flame is the only dangerous tile monsters still avoid.
		if not bombs.is_empty() and rng.randf() < ENEMY_BOMB_CHASE_CHANCE:
			var waiting_chance: float = _enemy_bomb_wait_chance(origin)
			if waiting_chance > 0.0:
				# Monsters briefly linger near a bomb, giving the player a fair
				# chance to catch them. Remote bombs cause a shorter wait.
				if rng.randf() < waiting_chance:
					continue
			else:
				var step_to_bomb: Vector2i = _enemy_step_toward_bomb(origin)
				if step_to_bomb != origin:
					bot["cell"] = step_to_bomb
					continue

		# No bomb nearby/reachable, or a rare independent decision:
		# wander and occasionally follow the player, as before.
		var candidates: Array[Vector2i] = []
		for d in DIRECTIONS:
			var next: Vector2i = origin + d
			if not _can_walk(next) or _cell_is_burning(next) or _enemy_tile_occupied(next, origin):
				continue
			candidates.append(next)
		if candidates.is_empty():
			continue
		var selected: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		if rng.randf() < 0.70:
			var closest: int = 999
			for candidate in candidates:
				var distance: int = absi(candidate.x - player_cell.x) + absi(candidate.y - player_cell.y)
				if distance < closest:
					closest = distance
					selected = candidate
		bot["cell"] = selected

func _enemy_tile_occupied(p: Vector2i, own_origin: Vector2i) -> bool:
	# The current enemy may use its own tile; another enemy blocks the route.
	if p == own_origin:
		return false
	for other in enemies:
		if other["cell"] == p:
			return true
	return false

func _enemy_bomb_wait_chance(p: Vector2i) -> float:
	var chance: float = 0.0
	for bomb in bombs:
		var pos: Vector2i = bomb["cell"]
		if absi(pos.x - p.x) + absi(pos.y - p.y) != 1:
			continue
		if bool(bomb["remote"]):
			chance = maxf(chance, ENEMY_REMOTE_BOMB_WAIT_CHANCE)
		else:
			return ENEMY_TIMED_BOMB_WAIT_CHANCE
	return chance

func _enemy_step_toward_bomb(start: Vector2i) -> Vector2i:
	# Shortest accessible route to ANY open tile adjacent to ANY bomb.
	# Unlike direct Manhattan steering, BFS routes around permanent walls,
	# crates and other monsters. It never walks through a bomb or fire.
	var goals: Dictionary = {}
	for bomb in bombs:
		var pos: Vector2i = bomb["cell"]
		for direction in DIRECTIONS:
			var near: Vector2i = pos + direction
			if _can_walk(near) and not _cell_is_burning(near):
				goals[near] = true
	if goals.is_empty() or goals.has(start):
		return start

	var visited: Dictionary = {}
	var first_step: Dictionary = {}
	var frontier: Array[Vector2i] = [start]
	var head: int = 0
	visited[start] = true
	while head < frontier.size():
		var current: Vector2i = frontier[head]
		head += 1
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if visited.has(next) or not _can_walk(next) or _cell_is_burning(next):
				continue
			if _enemy_tile_occupied(next, start):
				continue
			visited[next] = true
			first_step[next] = next if current == start else first_step[current]
			if goals.has(next):
				return first_step[next]
			frontier.append(next)
	return start

func _cell_is_burning(p: Vector2i) -> bool:
	for flame in flames:
		# Exactly the same active flame entries are used for drawing and damage.
		if flame["cell"] == p and float(flame["ttl"]) > 0.0:
			return true
	return false

func _check_player_hazards() -> void:
	if invulnerable > 0.0 or game_state != "playing":
		return
	if _cell_is_burning(player_cell):
		_hurt_player()
		return
	for bot in enemies:
		if bot["cell"] == player_cell:
			_hurt_player()
			return

func _hurt_player() -> void:
	if invulnerable > 0.0 or game_state != "playing":
		return
	lives -= 1
	_play_sound("hurt")
	if lives <= 0:
		_lost_game()
		return
	invulnerable = 2.0
	player_cell = Vector2i(1, 1)
	player_visual = Vector2(player_cell)
	# Always preserve a safe spawn route.
	_clear_spawn_zone(player_cell)

func _try_collect_revealed_reward() -> void:
	if reward_claimed or not reward_revealed or player_cell != dropped_reward_cell:
		return
	reward_claimed = true
	dropped_reward_cell = Vector2i(-1, -1)
	_apply_chosen_reward()
	reward_toast_time = 3.8
	_play_sound("pickup")

func _apply_chosen_reward() -> void:
	last_reward_kind = chosen_reward_kind
	match chosen_reward_kind:
		PU_RANGE:
			blast_range = mini(MAX_RANGE, blast_range + 1)
			last_reward_name = "PATLAMA MENZILI +1"
			last_reward_detail = "Sari + : Artik %d kare uzaga patlar." % blast_range
		PU_CAPACITY:
			max_bombs = mini(MAX_BOMBS, max_bombs + 1)
			last_reward_name = "BOMBA SAYISI +1"
			last_reward_detail = "Mor B : Ayni anda %d bomba koyabilirsin." % max_bombs
		PU_SPEED:
			speed_upgrade = mini(MAX_SPEED, speed_upgrade + 1)
			last_reward_name = "HAREKET HIZI +1"
			last_reward_detail = "Mavi > : Hiz gelistirme %d/%d." % [speed_upgrade, MAX_SPEED]
		PU_HEART:
			lives = mini(MAX_LIVES, lives + 1)
			last_reward_name = "EKSTRA CAN +1"
			last_reward_detail = "Pembe H : Can sayin %d oldu." % lives
		PU_REMOTE:
			remote_unlocked = true
			last_reward_name = "UZAKTAN PATLATMA ACILDI!"
			last_reward_detail = "Yesil D : SPACE ile bomba koy, E ile patlat."
		PU_KICK:
			kick_unlocked = true
			last_reward_name = "BOMBA KAYDIRMA ACILDI!"
			last_reward_detail = "Turuncu K : Bombaya dogru yuru; bomba kayar."
		PU_CRATE_PASS:
			crate_pass_unlocked = true
			last_reward_name = "KUTUDAN GECME ACILDI!"
			last_reward_detail = "Acik mavi G : Kirilabilir kutulardan yuruyebilirsin."
		_:
			score += 250
			last_reward_name = "+250 PUAN"
			last_reward_detail = "Tum gelistirmeler dolu. Bonus puan kazandin!"

func _win_level() -> void:
	# The player stepped into the revealed, unlocked door.
	game_state = "level_clear"
	level_transition_time = 1.5
	score += int(countdown) * 3 + 500
	_update_best_score()
	_play_sound("win")
	level += 1

func _lost_game() -> void:
	if game_state == "game_over":
		return
	game_state = "game_over"
	_update_best_score()
	_play_sound("hurt")

func _update_best_score() -> void:
	if score > best_score:
		best_score = score
		var config := ConfigFile.new()
		config.set_value("scores", "best", best_score)
		config.save("user://bomb_defender.cfg")

func _load_best_score() -> void:
	var config := ConfigFile.new()
	if config.load("user://bomb_defender.cfg") == OK:
		best_score = int(config.get_value("scores", "best", 0))

func _setup_sounds() -> void:
	for name in ["place", "explode", "pickup", "hurt", "win"]:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://audio/%s.wav" % name)
		player.volume_db = -9.0
		add_child(player)
		sounds[name] = player

func _play_sound(name: String) -> void:
	if sounds.has(name):
		(sounds[name] as AudioStreamPlayer).play()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 800)), BG)
	# Ambient circles give the static UI depth, even without sprite assets.
	draw_circle(Vector2(1190, 55), 180, Color("112840", 0.30))
	draw_circle(Vector2(70, 780), 190, Color("172d4a", 0.20))
	_draw_header()
	if game_state == "menu":
		_draw_menu()
		return
	_draw_board()
	_draw_sidebar()
	_draw_footer()
	if game_state == "playing" and reward_toast_time > 0.0:
		_draw_reward_toast()
	if game_state == "paused":
		_draw_overlay("DURAKLATILDI", "Devam etmek icin P veya ESC", "P / ESC")
	elif game_state == "game_over":
		_draw_overlay("OYUN BITTI", "Skor: %d  ·  Rekor: %d" % [score, best_score], "YENIDEN OYNA")
	elif game_state == "level_clear":
		_draw_overlay("ARENA TAMAMLANDI!", "Kapidan gectin! Siradaki arena: %d" % level, "HEMEN GEC")

func _font() -> Font:
	return ThemeDB.fallback_font

func _label(text: String, x: float, y: float, size: int = 18, color: Color = TEXT) -> void:
	draw_string(_font(), Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _panel(rect: Rect2, color: Color = PANEL) -> void:
	draw_rect(Rect2(rect.position + Vector2(0, 5), rect.size), Color("050914", 0.60), true)
	draw_rect(rect, color, true)
	draw_rect(rect, LINE, false, 1.3)

func _draw_header() -> void:
	_label("BOMB", 61, 65, 39, TEXT)
	_label("// DEFENDER", 168, 65, 28, CYAN)
	_label("BOMB DEFENDER", 63, 92, 13, MUTED)
	draw_line(Vector2(62, 109), Vector2(1217, 109), LINE, 2.0)

func _draw_board() -> void:
	_panel(Rect2(BOARD - Vector2(9, 9), Vector2(W * TILE + 18, H * TILE + 18)), Color("0e1728"))
	for y in range(H):
		for x in range(W):
			var p: Vector2 = BOARD + Vector2(x * TILE, y * TILE)
			var floor_color: Color = Color("1a2940") if (x + y) % 2 == 0 else Color("1c2d45")
			draw_rect(Rect2(p + Vector2.ONE, Vector2(TILE - 2, TILE - 2)), floor_color)
			if grid[y][x] == HARD:
				_draw_hard_tile(p)
			elif grid[y][x] == SOFT:
				_draw_soft_tile(p, x, y)
				if crate_pass_unlocked and player_cell == Vector2i(x, y):
					# A faint glow differentiates "standing within a crate".
					draw_rect(Rect2(p + Vector2(3, 3), Vector2(TILE - 6, TILE - 6)), Color("95e7ff", 0.25))
	# Exit is visible only after its *own* crate is destroyed.
	# It starts locked, and turns green when its conditions are met.
	if exit_revealed:
		_draw_exit_door()
	for bomb in bombs:
		_draw_bomb(bomb)
	for flame in flames:
		_draw_flame(flame)
	if reward_revealed and not reward_claimed:
		_draw_ground_reward()
	for enemy in enemies:
		_draw_enemy(enemy)
	if invulnerable <= 0.0 or int(elapsed * 9.0) % 2 == 0:
		_draw_hero(player_visual)

func _center(cell: Vector2i) -> Vector2:
	return BOARD + Vector2(cell) * float(TILE) + Vector2.ONE * (TILE / 2.0)

func _draw_hard_tile(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(3, 5), Vector2(39, 37)), Color("0a1324"))
	draw_rect(Rect2(p + Vector2(2, 2), Vector2(39, 36)), Color("354862"))
	draw_rect(Rect2(p + Vector2(5, 5), Vector2(33, 28)), Color("475f7b"))
	draw_rect(Rect2(p + Vector2(5, 5), Vector2(32, 3)), Color("6b87a3"))
	draw_line(p + Vector2(21, 9), p + Vector2(21, 34), Color("2b3c54"), 1.4)

func _draw_soft_tile(p: Vector2, x: int, y: int) -> void:
	draw_rect(Rect2(p + Vector2(4, 7), Vector2(37, 34)), Color("101622"))
	draw_rect(Rect2(p + Vector2(3, 3), Vector2(37, 34)), Color("b67446"))
	draw_rect(Rect2(p + Vector2(7, 7), Vector2(29, 25)), Color("da9762"))
	draw_rect(Rect2(p + Vector2(7, 7), Vector2(29, 4)), Color("f2b27b"))
	draw_line(p + Vector2(9, 12), p + Vector2(32, 29), Color("905230"), 3)
	draw_line(p + Vector2(32, 12), p + Vector2(9, 29), Color("905230"), 3)
	if (x + y) % 3 == 0:
		draw_rect(Rect2(p + Vector2(18, 17), Vector2(7, 7)), Color("f0bd83"))

func _draw_hero(cell_visual: Vector2) -> void:
	var c: Vector2 = BOARD + cell_visual * TILE + Vector2.ONE * (TILE * 0.5)
	draw_ellipse_fake(c + Vector2(0, 15), Vector2(17, 7), Color("050d1b", 0.75))
	draw_circle(c + Vector2(0, 2), 16, Color("0c4b66"))
	draw_circle(c + Vector2(0, -2), 15, CYAN)
	draw_rect(Rect2(c + Vector2(-11, -4), Vector2(22, 11)), Color("183f5a"))
	draw_circle(c + Vector2(-5, 1), 2.8, Color.WHITE)
	draw_circle(c + Vector2(5, 1), 2.8, Color.WHITE)
	draw_rect(Rect2(c + Vector2(-9, 11), Vector2(6, 6)), Color("f6fbff"))
	draw_rect(Rect2(c + Vector2(3, 11), Vector2(6, 6)), Color("f6fbff"))
	draw_circle(c + Vector2(-7, -12), 4, Color("b2f9ff"))

func draw_ellipse_fake(center: Vector2, radii: Vector2, color: Color) -> void:
	# Small procedural shadow without textures.
	for index in range(4):
		draw_circle(center + Vector2(0, index * 0.55), radii.x - index * 1.9, Color(color, color.a * 0.18))

func _draw_enemy(bot: Dictionary) -> void:
	var bot_pos: Vector2 = bot["visual"]
	var c: Vector2 = BOARD + bot_pos * TILE + Vector2.ONE * (TILE * 0.5)
	var main: Color = PINK if int(bot["kind"]) == 0 else Color("bb92ff")
	draw_circle(c + Vector2(0, 3), 16, Color("45172d") if int(bot["kind"]) == 0 else Color("39244d"))
	draw_circle(c + Vector2(0, -2), 15, main)
	draw_rect(Rect2(c + Vector2(-11, -3), Vector2(22, 11)), Color("241c36"))
	draw_circle(c + Vector2(-5, 1), 2.5, Color.WHITE)
	draw_circle(c + Vector2(5, 1), 2.5, Color.WHITE)
	draw_line(c + Vector2(-9, -14), c + Vector2(-13, -21), main, 2)
	draw_line(c + Vector2(9, -14), c + Vector2(13, -21), main, 2)

func _draw_bomb(bomb: Dictionary) -> void:
	var c: Vector2 = _center(bomb["cell"])
	var remote: bool = bool(bomb["remote"])
	var danger: float = 0.0 if remote else 1.0 - clampf(float(bomb["fuse"]) / 2.15, 0.0, 1.0)
	var pulse: float = 1.5 * sin(elapsed * (8 + danger * 13))
	var outer_color: Color = Color("1d6756") if remote else Color("38304f")
	var shine_color: Color = Color("8cf8c4") if remote else Color("aaa4c3")
	draw_circle(c + Vector2(0, 3), 17, Color("0a0717", 0.7))
	draw_circle(c, 14 + pulse, outer_color)
	draw_circle(c + Vector2(-3, -3), 9.5, Color("39967b") if remote else Color("635a79"))
	draw_circle(c + Vector2(-6, -7), 3.8, shine_color)
	draw_line(c + Vector2(5, -12), c + Vector2(9, -19), shine_color if remote else GOLD, 3)
	draw_circle(c + Vector2(9, -19), 3.0 + danger * 2.0, shine_color if remote else (PINK if danger > 0.6 else GOLD))
	if remote:
		_label("E", c.x - 5, c.y + 6, 13, Color("d5ffeb"))

func _draw_flame(flame: Dictionary) -> void:
	var c: Vector2 = _center(flame["cell"])
	# Keep dangerous flames clearly visible up to their final active frame.
	var factor: float = clampf(float(flame["ttl"]) / FLAME_DURATION, 0.58, 1.0)
	draw_rect(Rect2(c - Vector2(20, 20), Vector2(40, 40)), Color("fa704f", 0.28 * factor))
	draw_rect(Rect2(c - Vector2(14, 21), Vector2(28, 42)), Color("ff974f", 0.85 * factor))
	draw_rect(Rect2(c - Vector2(21, 14), Vector2(42, 28)), Color("ff974f", 0.85 * factor))
	draw_rect(Rect2(c - Vector2(8, 17), Vector2(16, 34)), Color("ffe785", 0.95 * factor))
	draw_rect(Rect2(c - Vector2(17, 8), Vector2(34, 16)), Color("ffe785", 0.95 * factor))
	draw_circle(c, 7, Color("fff8dc", factor))

func _reward_color(kind: int) -> Color:
	match kind:
		PU_RANGE:
			return GOLD
		PU_CAPACITY:
			return Color("d1a1ff")
		PU_SPEED:
			return CYAN
		PU_HEART:
			return PINK
		PU_REMOTE:
			return Color("62f0b2")
		PU_KICK:
			return Color("ffa46c")
		PU_CRATE_PASS:
			return Color("8acbff")
	return MUTED

func _draw_reward_icon(center: Vector2, kind: int, radius: float = 15.0) -> void:
	var color: Color = _reward_color(kind)
	draw_circle(center, radius + 2.0, Color("0b1220"))
	draw_circle(center, radius, color)
	draw_circle(center, radius * 0.70, Color("26334d"))
	var symbol: String = "?"
	match kind:
		PU_RANGE: symbol = "+"
		PU_CAPACITY: symbol = "B"
		PU_SPEED: symbol = ">"
		PU_HEART: symbol = "H"
		PU_REMOTE: symbol = "D"
		PU_KICK: symbol = "K"
		PU_CRATE_PASS: symbol = "G"
	var font_size: int = maxi(13, int(radius * 1.25))
	_label(symbol, center.x - float(font_size) * 0.31, center.y + float(font_size) * 0.37, font_size, color)

func _draw_exit_door() -> void:
	var center: Vector2 = _center(revealed_exit_cell)
	var open_now: bool = _exit_is_open()
	var frame_color: Color = Color("4af0bd") if open_now else Color("e8ab65")
	var inside_color: Color = Color("0f725c") if open_now else Color("47334e")
	var door_top_left: Vector2 = center + Vector2(-18, -20)
	# Dark outline and an arched doorway drawn without external assets.
	draw_rect(Rect2(door_top_left + Vector2(-2, 3), Vector2(40, 39)), Color("080e20"))
	draw_rect(Rect2(door_top_left, Vector2(36, 37)), frame_color)
	draw_rect(Rect2(door_top_left + Vector2(4, 4), Vector2(28, 33)), inside_color)
	draw_circle(center + Vector2(0, -9), 10, inside_color)
	if open_now:
		draw_circle(center, 13 + sin(elapsed * 6.0) * 2.0, Color("43ffbf", 0.25))
		_label(">", center.x - 7, center.y + 8, 24, Color("d8fff0"))
	else:
		# Small lock: visible door, but not usable until objectives are met.
		draw_arc(center + Vector2(0, -2), 6, PI, TAU, 12, GOLD, 2.5)
		draw_rect(Rect2(center + Vector2(-8, -1), Vector2(16, 13)), GOLD)
		draw_circle(center + Vector2(0, 3), 2.1, Color("4c3046"))

func _draw_ground_reward() -> void:
	var center: Vector2 = _center(dropped_reward_cell)
	var pulse: float = sin(elapsed * 6.0)
	draw_circle(center, 22.0 + pulse * 2.0, Color(GOLD, 0.18))
	if chosen_reward_kind >= 0:
		_draw_reward_icon(center, chosen_reward_kind, 17.0)
	else:
		draw_circle(center, 17, GOLD)
		_label("$", center.x - 6, center.y + 7, 20, Color("26334d"))

func _draw_reward_toast() -> void:
	var rect: Rect2 = Rect2(157, 147, 570, 75)
	draw_rect(rect, Color("0d1c2e", 0.94), true)
	draw_rect(rect, GOLD, false, 2.0)
	if last_reward_kind >= 0:
		_draw_reward_icon(Vector2(195, 183), last_reward_kind, 17.0)
	else:
		_label("+", 187, 189, 26, GOLD)
	_label(last_reward_name, 228, 178, 20, GOLD)
	_label(last_reward_detail, 228, 203, 14, TEXT)

func _draw_sidebar() -> void:
	_panel(Rect2(842, 123, 376, 601))
	_label("OYUN DURUMU", 868, 153, 18, CYAN)
	draw_line(Vector2(868, 163), Vector2(1189, 163), LINE, 1)
	_label("ARENA", 868, 187, 13, MUTED)
	_label(str(level), 868, 220, 29, TEXT)
	_label("SKOR", 1030, 187, 13, MUTED)
	_label(str(score), 1030, 220, 29, GOLD)
	draw_line(Vector2(868, 235), Vector2(1189, 235), LINE, 1)
	_label("CAN", 868, 258, 13, MUTED)
	for i in range(MAX_LIVES):
		var color: Color = PINK if i < lives else Color("3c3043")
		draw_circle(Vector2(881 + i * 31, 282), 9, color)
	_label("KALAN SURE", 1050, 258, 13, MUTED)
	_label(_clock_text(), 1050, 288, 21, GOLD if countdown < 30.0 else TEXT)
	draw_line(Vector2(868, 306), Vector2(1189, 306), LINE, 1)
	_label("GELISTIRME SIMGELERI", 868, 329, 15, CYAN)
	var reward_status: String = "1 kutuda 1 gizli odul (ozel yetenek dahil)!"
	if reward_claimed:
		reward_status = "Odulu topladin! Cikisa hazirlan."
	elif reward_revealed:
		reward_status = "Odul ortaya cikti! Uzerine yuru."
	_label(reward_status, 868, 346, 11, GOLD if reward_revealed and not reward_claimed else MUTED)
	_draw_reward_legend_row(352, PU_RANGE, "PATLAMA MENZILI", "Patlama +1 kare", "%d/%d" % [blast_range, MAX_RANGE])
	_draw_reward_legend_row(391, PU_CAPACITY, "BOMBA SAYISI", "Ayni anda +1 bomba", "%d/%d" % [max_bombs, MAX_BOMBS])
	_draw_reward_legend_row(430, PU_SPEED, "HAREKET HIZI", "Daha hizli hareket", "%d/%d" % [speed_upgrade, MAX_SPEED])
	_draw_reward_legend_row(469, PU_HEART, "EKSTRA CAN", "Canina +1 ekler", "%d/%d" % [lives, MAX_LIVES])
	_draw_reward_legend_row(508, PU_REMOTE, "UZAKTAN PATLATMA", "E: Bombayi patlat", "ACIK" if remote_unlocked else "YOK")
	_draw_reward_legend_row(547, PU_KICK, "BOMBA KAYDIRMA", "Bombaya dogru yuru", "ACIK" if kick_unlocked else "YOK")
	_draw_reward_legend_row(586, PU_CRATE_PASS, "KUTUDAN GECME", "Kirilabilir kutudan gec", "ACIK" if crate_pass_unlocked else "YOK")
	draw_line(Vector2(868, 631), Vector2(1189, 631), LINE, 1)
	_label("RAKIP SAYISI", 868, 651, 12, MUTED)
	_label(str(enemies.size()), 1140, 651, 17, PINK)
	_label("REKOR", 868, 679, 12, MUTED)
	_label(str(best_score), 1081, 679, 17, GOLD)
	if not exit_revealed:
		_label("KAPI: Rastgele bir kutunun icinde gizli!", 868, 708, 12, GOLD)
	elif _exit_is_open():
		_label("KAPI ACIK! Yesil kapiya gir.", 868, 708, 13, Color("64f0c9"))
	elif not reward_claimed and not enemies.is_empty():
		_label("KAPI KILITLI: Odulu al, rakipleri yen.", 868, 708, 12, GOLD)
	elif not reward_claimed:
		_label("KAPI KILITLI: Gizli odulu topla.", 868, 708, 12, GOLD)
	else:
		_label("KAPI KILITLI: Tum rakipleri yen.", 868, 708, 12, MUTED)

func _draw_reward_legend_row(top: float, kind: int, title: String, explanation: String, value: String) -> void:
	draw_rect(Rect2(867, top, 321, 36), Color("17243b"))
	_draw_reward_icon(Vector2(887, top + 18), kind, 11.0)
	_label(title, 908, top + 15, 11, TEXT)
	_label(explanation, 908, top + 30, 10, MUTED)
	_label(value, 1150, top + 23, 11, _reward_color(kind))

func _clock_text() -> String:
	var seconds: int = maxi(0, int(ceil(countdown)))
	return "%02d:%02d" % [seconds / 60, seconds % 60]

func _draw_footer() -> void:
	_label("WASD / OKLAR: HAREKET", 62, 744, 14, MUTED)
	_label("SPACE: BOMBA", 328, 744, 14, GOLD)
	_label("E: UZAKTAN", 515, 744, 14, Color("62f0b2") if remote_unlocked else MUTED)
	_label("P / ESC: DURAKLAT", 728, 744, 14, MUTED)
	_label("R: YENI OYUN", 994, 744, 14, MUTED)
	var kick_status: String = "BOMBAYA YURU = KAYDIR (K: %s)" % ("ACIK" if kick_unlocked else "KILITLI")
	var pass_status: String = "KUTU ICINDEN GEC (G: %s)" % ("ACIK" if crate_pass_unlocked else "KILITLI")
	_label(kick_status, 62, 777, 12, Color("ffa46c") if kick_unlocked else MUTED)
	_label(pass_status, 436, 777, 12, Color("8acbff") if crate_pass_unlocked else MUTED)
	_label("Bomb Defender", 953, 777, 12, Color("60748e"))

func _draw_menu() -> void:
	_panel(Rect2(249, 164, 782, 459))
	_label("BOMB DEFENDER", 410, 249, 38, CYAN)
	_label("BOMBANI YERLESTIR, RAKIPLERI YEN!", 323, 307, 23, TEXT)
	_label("Her bolum: 1 kutuda odul, baska 1 kutuda kapi.", 357, 366, 16, MUTED)
	_label("Kutu odullerinde K: bomba kaydir, G: kutudan gec, D: uzaktan patlat.", 297, 404, 14, MUTED)
	_label("BOLUMU BITIR: ODULU AL + RAKIPLERI YEN + KAPIYA GIR!", 328, 443, 14, GOLD)
	_draw_primary_button("OYUNA BASLA")
	_label("ENTER: Basla  |  WASD: Yuru  |  SPACE: Bomba  |  E: Uzaktan patlat", 348, 578, 14, MUTED)

func _draw_primary_button(text: String) -> void:
	var rect: Rect2 = Rect2(486, 478, 308, 62)
	draw_rect(Rect2(rect.position + Vector2(0, 5), rect.size), Color("0d3949"))
	draw_rect(rect, CYAN)
	_label(text, 541 if text == "OYUNA BASLA" else 520, 517, 20, Color("082034"))

func _draw_overlay(title: String, subtitle: String, button_text: String) -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 800)), Color("050912", 0.78))
	_panel(Rect2(315, 216, 650, 358), Color("16233b"))
	var title_x: float = 382 if title == "ARENA TAMAMLANDI!" else 468
	_label(title, title_x, 312, 31, CYAN if game_state == "level_clear" else (PINK if game_state == "game_over" else TEXT))
	_label(subtitle, 416, 376, 19, MUTED)
	if game_state == "level_clear":
		_label("Yeni bolume otomatik geciliyor...", 442, 431, 18, GOLD)
	if game_state != "paused":
		_draw_primary_button(button_text)
	else:
		_label("R ile oyunu yeniden baslatabilirsin", 444, 505, 15, MUTED)
