// Copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <AppKit/NSEvent.h>
#include <Carbon/Carbon.h>

#include "chrome/browser/global_keyboard_shortcuts_mac.h"

#include "base/basictypes.h"
#include "base/logging.h"
#include "chrome/app/chrome_command_ids.h"

// Basically, there are two kinds of keyboard shortcuts: Ones that should work
// only if the tab contents is focused (BrowserKeyboardShortcut), and ones that
// should work in all other cases (WindowKeyboardShortcut). In the latter case,
// we differentiate between shortcuts that are checked before any other view
// gets the chance to handle them (WindowKeyboardShortcut) or after all views
// had a chance but did not handle the keypress event
// (DelayedWindowKeyboardShortcut).

const KeyboardShortcutData* GetWindowKeyboardShortcutTable(
    size_t* num_entries) {
  static const KeyboardShortcutData keyboard_shortcuts[] = {
    //cmd   shift  cntrl  option
    //---   -----  -----  ------
    // '{' / '}' characters should be matched earlier than virtual key code
    // (therefore we can match alt-8 as '{' on german keyboards).
    {true,  false, false, false, 0,             '}', IDC_SELECT_NEXT_TAB},
    {true,  false, false, false, 0,             '{', IDC_SELECT_PREVIOUS_TAB},
    {false, false, true,  false, kVK_PageDown,  0,   IDC_SELECT_NEXT_TAB},
    {false, false, true,  false, kVK_Tab,       0,   IDC_SELECT_NEXT_TAB},
    {false, false, true,  false, kVK_PageUp,    0,   IDC_SELECT_PREVIOUS_TAB},
    {false, true,  true,  false, kVK_Tab,       0,   IDC_SELECT_PREVIOUS_TAB},
    // Cmd-0..8 select the Nth tab, with cmd-9 being "last tab".
    {true,  false, false, false, kVK_ANSI_1,          0, IDC_SELECT_TAB_0},
    {true,  false, false, false, kVK_ANSI_Keypad1,    0, IDC_SELECT_TAB_0},
    {true,  false, false, false, kVK_ANSI_2,          0, IDC_SELECT_TAB_1},
    {true,  false, false, false, kVK_ANSI_Keypad2,    0, IDC_SELECT_TAB_1},
    {true,  false, false, false, kVK_ANSI_3,          0, IDC_SELECT_TAB_2},
    {true,  false, false, false, kVK_ANSI_Keypad3,    0, IDC_SELECT_TAB_2},
    {true,  false, false, false, kVK_ANSI_4,          0, IDC_SELECT_TAB_3},
    {true,  false, false, false, kVK_ANSI_Keypad4,    0, IDC_SELECT_TAB_3},
    {true,  false, false, false, kVK_ANSI_5,          0, IDC_SELECT_TAB_4},
    {true,  false, false, false, kVK_ANSI_Keypad5,    0, IDC_SELECT_TAB_4},
    {true,  false, false, false, kVK_ANSI_6,          0, IDC_SELECT_TAB_5},
    {true,  false, false, false, kVK_ANSI_Keypad6,    0, IDC_SELECT_TAB_5},
    {true,  false, false, false, kVK_ANSI_7,          0, IDC_SELECT_TAB_6},
    {true,  false, false, false, kVK_ANSI_Keypad7,    0, IDC_SELECT_TAB_6},
    {true,  false, false, false, kVK_ANSI_8,          0, IDC_SELECT_TAB_7},
    {true,  false, false, false, kVK_ANSI_Keypad8,    0, IDC_SELECT_TAB_7},
    {true,  false, false, false, kVK_ANSI_9,          0, IDC_SELECT_LAST_TAB},
    {true,  false, false, false, kVK_ANSI_Keypad9,    0, IDC_SELECT_LAST_TAB},
  };

  *num_entries = arraysize(keyboard_shortcuts);

  return keyboard_shortcuts;
}

const KeyboardShortcutData* GetDelayedWindowKeyboardShortcutTable(
    size_t* num_entries) {
  static const KeyboardShortcutData keyboard_shortcuts[] = {
    //cmd   shift  cntrl  option
    //---   -----  -----  ------
    {false, false, false, false, kVK_Escape,        0, IDC_STOP},
  };

  *num_entries = arraysize(keyboard_shortcuts);

  return keyboard_shortcuts;
}

const KeyboardShortcutData* GetBrowserKeyboardShortcutTable(
    size_t* num_entries) {
  static const KeyboardShortcutData keyboard_shortcuts[] = {
    //cmd   shift  cntrl  option
    //---   -----  -----  ------
    {true,  false, false, false, kVK_LeftArrow,    0,   IDC_BACK},
    {true,  false, false, false, kVK_RightArrow,   0,   IDC_FORWARD},
    {false, false, false, false, kVK_Delete,       0,   IDC_BACK},
    {false, true,  false, false, kVK_Delete,       0,   IDC_FORWARD},
    {true,  true,  false, false, 0,                'c', IDC_DEV_TOOLS_INSPECT},
  };

  *num_entries = arraysize(keyboard_shortcuts);

  return keyboard_shortcuts;
}

static bool MatchesEventForKeyboardShortcut(
    const KeyboardShortcutData& shortcut,
    bool command_key, bool shift_key, bool cntrl_key, bool opt_key,
    int vkey_code, unichar key_char) {
  // Expects that one of |key_char| or |vkey_code| is 0.
  DCHECK((shortcut.key_char == 0) ^ (shortcut.vkey_code == 0));
  if (shortcut.key_char) {
    // The given shortcut key is to be matched by a keyboard character.
    // In this case we ignore shift and opt (alt) key modifiers, because
    // the character may be generated by a combination with those keys.
    if (shortcut.command_key == command_key &&
        shortcut.cntrl_key == cntrl_key &&
        shortcut.key_char == key_char)
      return true;
  } else if (shortcut.vkey_code) {
    // The given shortcut key is to be matched by a virtual key code.
    if (shortcut.command_key == command_key &&
        shortcut.shift_key == shift_key &&
        shortcut.cntrl_key == cntrl_key &&
        shortcut.opt_key == opt_key &&
        shortcut.vkey_code == vkey_code)
      return true;
  } else {
    NOTREACHED();  // Shouldn't happen.
  }
  return false;
}

static int CommandForKeyboardShortcut(
    const KeyboardShortcutData* (*get_keyboard_shortcut_table)(size_t*),
    bool command_key, bool shift_key, bool cntrl_key, bool opt_key,
    int vkey_code, unichar key_char) {

  // Scan through keycodes and see if it corresponds to one of the global
  // shortcuts on file.
  //
  // TODO(jeremy): Change this into a hash table once we get enough
  // entries in the array to make a difference.
  // (When turning this into a hash table, note that the current behavior
  // relies on the order of the table (see the comment for '{' / '}' above).
  size_t num_shortcuts = 0;
  const KeyboardShortcutData *it = get_keyboard_shortcut_table(&num_shortcuts);
  for (size_t i = 0; i < num_shortcuts; ++i, ++it) {
    if (MatchesEventForKeyboardShortcut(*it, command_key, shift_key, cntrl_key,
                                        opt_key, vkey_code, key_char))
      return it->chrome_command;
  }

  return -1;
}

int CommandForWindowKeyboardShortcut(
    bool command_key, bool shift_key, bool cntrl_key, bool opt_key,
    int vkey_code, unichar key_char) {
  return CommandForKeyboardShortcut(GetWindowKeyboardShortcutTable,
                                    command_key, shift_key,
                                    cntrl_key, opt_key, vkey_code,
                                    key_char);
}

int CommandForDelayedWindowKeyboardShortcut(
    bool command_key, bool shift_key, bool cntrl_key, bool opt_key,
    int vkey_code, unichar key_char) {
  return CommandForKeyboardShortcut(GetDelayedWindowKeyboardShortcutTable,
                                    command_key, shift_key,
                                    cntrl_key, opt_key, vkey_code,
                                    key_char);
}

int CommandForBrowserKeyboardShortcut(
    bool command_key, bool shift_key, bool cntrl_key, bool opt_key,
    int vkey_code, unichar key_char) {
  return CommandForKeyboardShortcut(GetBrowserKeyboardShortcutTable,
                                    command_key, shift_key,
                                    cntrl_key, opt_key, vkey_code,
                                    key_char);
}

unichar KeyCharacterForEvent(NSEvent* event) {
  NSString* eventString = [event charactersIgnoringModifiers];
  NSString* characters = [event characters];

  // Character pairs that undergo BiDi mirrored.
  // There are actually many more such pairs, but these are the ones that
  // are likely to show up in keyboard shortcuts.
  const struct {
    unichar a;
    unichar b;
  } kMirroredBiDiChars[] = {
    {'{', '}'},
    {'[', ']'},
    {'(', ')'},
  };

  if ([eventString length] != 1)
    return 0;

  if ([characters length] != 1)
    return [eventString characterAtIndex:0];

  unichar noModifiersChar = [eventString characterAtIndex:0];
  unichar rawChar = [characters characterAtIndex:0];
  // When both |characters| and |charactersIgnoringModifiers| are ascii,
  // return the first character of |characters|, if...
  if (isascii(noModifiersChar) && isascii(rawChar)) {
    // |characters| is an alphabet (mainly for dvorak-qwerty layout), or
    if (isalpha(rawChar))
      return rawChar;

    // http://crbug.com/42517
    // In RTL keyboard layouts, Cocoa mirrors characters in the string
    // returned by [event charactersIgnoringModifiers].  In this case, return
    // the raw (unmirrored) char.
    // FIXME: If there is a need to add any more characters to the
    // kMirroredBiDiChars table, then it's probably better to use ICU's
    // u_charMirror() function to perform this test.
    for (size_t i = 0; i < ARRAYSIZE_UNSAFE(kMirroredBiDiChars); ++i) {
      const unichar& a = kMirroredBiDiChars[i].a;
      const unichar& b = kMirroredBiDiChars[i].b;
      if ((rawChar == a && noModifiersChar == b) ||
          (rawChar == b && noModifiersChar == a))
          return rawChar;
    }

    // opt/alt modifier is set (e.g. on german layout we want '{' for opt-8).
    if ([event modifierFlags] & NSAlternateKeyMask)
      return [characters characterAtIndex:0];
  }

  return [eventString characterAtIndex:0];
}