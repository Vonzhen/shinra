/**
 * Shinra | generator_util.uc | v1.0
 */

'use strict';

function upper_text(value) {
	let text = "" + value;
	text = replace(text, "a", "A");
	text = replace(text, "b", "B");
	text = replace(text, "c", "C");
	text = replace(text, "d", "D");
	text = replace(text, "e", "E");
	text = replace(text, "f", "F");
	text = replace(text, "g", "G");
	text = replace(text, "h", "H");
	text = replace(text, "i", "I");
	text = replace(text, "j", "J");
	text = replace(text, "k", "K");
	text = replace(text, "l", "L");
	text = replace(text, "m", "M");
	text = replace(text, "n", "N");
	text = replace(text, "o", "O");
	text = replace(text, "p", "P");
	text = replace(text, "q", "Q");
	text = replace(text, "r", "R");
	text = replace(text, "s", "S");
	text = replace(text, "t", "T");
	text = replace(text, "u", "U");
	text = replace(text, "v", "V");
	text = replace(text, "w", "W");
	text = replace(text, "x", "X");
	text = replace(text, "y", "Y");
	text = replace(text, "z", "Z");
	return text;
}

function tag_contains_keyword(tag_upper, keyword) {
	if (type(keyword) != "string" || keyword == "")
		return false;
	return index(tag_upper, upper_text(keyword)) >= 0;
}

function is_digit(ch) {
	return ch == "0" || ch == "1" || ch == "2" || ch == "3" || ch == "4" || ch == "5" || ch == "6" || ch == "7" || ch == "8" || ch == "9";
}

function append_unique(list, value) {
	if (type(value) != "string" || value == "")
		return;

	for (let item in list) {
		if (item == value)
			return;
	}

	push(list, value);
}

export { append_unique, upper_text, tag_contains_keyword, is_digit };
