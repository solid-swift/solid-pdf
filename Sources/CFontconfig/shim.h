#include <fontconfig/fontconfig.h>
#include <stddef.h>
#include <string.h>

static inline int solid_fc_match_font(
  const char *postscript_name,
  char *path,
  size_t path_capacity,
  int *face_index,
  char *resolved_name,
  size_t name_capacity
) {
  FcPattern *query = FcPatternCreate();
  FcResult result;
  FcPattern *match;
  FcChar8 *file = NULL;
  FcChar8 *name = NULL;
  int index = 0;
  if (query == NULL) return 0;
  FcPatternAddString(query, FC_POSTSCRIPT_NAME, (const FcChar8 *)postscript_name);
  FcConfigSubstitute(NULL, query, FcMatchPattern);
  FcDefaultSubstitute(query);
  match = FcFontMatch(NULL, query, &result);
  FcPatternDestroy(query);
  if (match == NULL) return 0;
  if (FcPatternGetString(match, FC_FILE, 0, &file) != FcResultMatch || file == NULL) {
    FcPatternDestroy(match);
    return 0;
  }
  FcPatternGetInteger(match, FC_INDEX, 0, &index);
  FcPatternGetString(match, FC_POSTSCRIPT_NAME, 0, &name);
  if (strlen((const char *)file) + 1 > path_capacity) {
    FcPatternDestroy(match);
    return 0;
  }
  strcpy(path, (const char *)file);
  if (name != NULL && strlen((const char *)name) + 1 <= name_capacity) {
    strcpy(resolved_name, (const char *)name);
  } else if (name_capacity > 0) {
    resolved_name[0] = '\0';
  }
  *face_index = index;
  FcPatternDestroy(match);
  return 1;
}

static inline size_t solid_fc_postscript_names(char *buffer, size_t capacity) {
  FcPattern *pattern = FcPatternCreate();
  FcObjectSet *objects = FcObjectSetBuild(FC_POSTSCRIPT_NAME, NULL);
  FcFontSet *fonts;
  size_t required = 0;
  int index;
  if (pattern == NULL || objects == NULL) {
    if (pattern != NULL) FcPatternDestroy(pattern);
    if (objects != NULL) FcObjectSetDestroy(objects);
    return 0;
  }
  fonts = FcFontList(NULL, pattern, objects);
  FcPatternDestroy(pattern);
  FcObjectSetDestroy(objects);
  if (fonts == NULL) return 0;
  for (index = 0; index < fonts->nfont; index += 1) {
    FcChar8 *name = NULL;
    if (FcPatternGetString(fonts->fonts[index], FC_POSTSCRIPT_NAME, 0, &name) == FcResultMatch) {
      size_t length = strlen((const char *)name) + 1;
      if (buffer != NULL && required + length <= capacity) {
        memcpy(buffer + required, name, length);
      }
      required += length;
    }
  }
  FcFontSetDestroy(fonts);
  return required;
}
