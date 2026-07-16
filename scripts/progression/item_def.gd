class_name ItemDef
extends RefCounted

enum Kind { SPELL_BOOK, SKILL_BOOK, HEALTH_BOOK }

var id: StringName = &""
var display_name: String = ""
var kind: Kind = Kind.SPELL_BOOK
## For books: ability id, or empty for health books.
var ability_id: StringName = &""
var health_bonus: int = 0
var description: String = ""
