#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_GLYPH_H
#include FT_OUTLINE_H
#include FT_FONT_FORMATS_H
#include <stddef.h>

typedef struct {
  int kind;
  FT_Pos x1;
  FT_Pos y1;
  FT_Pos x2;
  FT_Pos y2;
  FT_Pos x3;
  FT_Pos y3;
} SolidFTOutlineEvent;

typedef struct {
  SolidFTOutlineEvent *events;
  size_t capacity;
  size_t count;
} SolidFTOutlineCollector;

static inline void solid_ft_append_event(
  SolidFTOutlineCollector *collector,
  int kind,
  const FT_Vector *first,
  const FT_Vector *second,
  const FT_Vector *third
) {
  if (collector->count < collector->capacity) {
    SolidFTOutlineEvent *event = &collector->events[collector->count];
    event->kind = kind;
    event->x1 = first == NULL ? 0 : first->x;
    event->y1 = first == NULL ? 0 : first->y;
    event->x2 = second == NULL ? 0 : second->x;
    event->y2 = second == NULL ? 0 : second->y;
    event->x3 = third == NULL ? 0 : third->x;
    event->y3 = third == NULL ? 0 : third->y;
  }
  collector->count += 1;
}

static inline int solid_ft_move_to(const FT_Vector *to, void *user) {
  solid_ft_append_event((SolidFTOutlineCollector *)user, 0, to, NULL, NULL);
  return 0;
}

static inline int solid_ft_line_to(const FT_Vector *to, void *user) {
  solid_ft_append_event((SolidFTOutlineCollector *)user, 1, to, NULL, NULL);
  return 0;
}

static inline int solid_ft_conic_to(const FT_Vector *control, const FT_Vector *to, void *user) {
  solid_ft_append_event((SolidFTOutlineCollector *)user, 2, control, to, NULL);
  return 0;
}

static inline int solid_ft_cubic_to(
  const FT_Vector *first,
  const FT_Vector *second,
  const FT_Vector *to,
  void *user
) {
  solid_ft_append_event((SolidFTOutlineCollector *)user, 3, first, second, to);
  return 0;
}

static inline size_t solid_ft_outline_events(
  FT_Outline *outline,
  SolidFTOutlineEvent *events,
  size_t capacity
) {
  SolidFTOutlineCollector collector = { events, capacity, 0 };
  FT_Outline_Funcs functions = {
    solid_ft_move_to,
    solid_ft_line_to,
    solid_ft_conic_to,
    solid_ft_cubic_to,
    0,
    0
  };
  if (FT_Outline_Decompose(outline, &functions, &collector) != 0) return 0;
  return collector.count;
}
