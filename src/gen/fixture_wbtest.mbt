///|
/// The generated types file for a spec that declares nothing but `type` blocks.
fn typed(src : String) -> String raise {
  generate(@api.parse(src))
}

///|
fn contains(haystack : String, needle : String) -> Bool {
  let hn = haystack.length()
  let nn = needle.length()
  if nn == 0 {
    return true
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut ok = true
    for j = 0; j < nn; j = j + 1 {
      if haystack[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return true
    }
  }
  false
}

///|
test "a default= fills in what the request left out" {
  let code = typed(
    (
      #|type CreateReq {
      #|  page: int    `form:"page,default=1"`
      #|  sort: string `form:"sort,default=asc"`
      #|  size: int    `form:"size"`
      #|}
    ),
  )
  assert_eq(
    contains(
      code,
      (
        #|pub fn CreateReq::with_defaults(self : CreateReq) -> CreateReq {
        #|  {
        #|    ..self,
        #|    page: if self.page == 0 { 1 } else { self.page },
        #|    sort: if self.sort == "" { "asc" } else { self.sort },
        #|  }
        #|}
      ),
    ),
    true,
  )
  // a field with no default is left where the request put it
  assert_eq(contains(code, "size: if"), false)
}

///|
test "options= and range= become the checks the service runs" {
  let code = typed(
    (
      #|type CreateReq {
      #|  name: string `json:"name"`
      #|  nick: string `json:"nick,optional"`
      #|  page: int    `form:"page,range=[1:100]"`
      #|  sort: string `form:"sort,options=asc|desc"`
      #|}
    ),
  )
  assert_eq(
    contains(
      code,
      (
        #|  if self.name == "" {
        #|    return Some("name is required")
        #|  }
      ),
    ),
    true,
  )
  // an optional field is allowed through empty
  assert_eq(contains(code, "nick is required"), false)
  assert_eq(
    contains(
      code,
      (
        #|  if self.page < 1 || self.page > 100 {
        #|    return Some("page is out of range [1:100]")
        #|  }
      ),
    ),
    true,
  )
  assert_eq(
    contains(
      code,
      (
        #|  if self.sort != "asc" && self.sort != "desc" {
        #|    return Some("sort is not one of asc|desc")
        #|  }
      ),
    ),
    true,
  )
  assert_eq(
    contains(code, "pub fn CreateReq::check(self : CreateReq) -> String?"),
    true,
  )
  // nothing declared a default, so there is nothing to fill in
  assert_eq(contains(code, "with_defaults"), false)
}

///|
test "an open range bounds only the end the tag closed" {
  let code = typed(
    (
      #|type Q {
      #|  from: int64  `form:"from,range=[10:]"`
      #|  rate: float64 `form:"rate,range=(0:1)"`
      #|}
    ),
  )
  assert_eq(contains(code, "if self.from < 10L {"), true)
  assert_eq(contains(code, "self.from >"), false)
  // an exclusive bound refuses the bound itself
  assert_eq(contains(code, "if self.rate <= 0.0 || self.rate >= 1.0 {"), true)
}

///|
test "a message the tags constrain in no way generates no checks" {
  let code = typed("type Plain {\n  id: int64\n  n: int\n}")
  assert_eq(contains(code, "pub(all) struct Plain {"), true)
  assert_eq(contains(code, "Plain::check"), false)
  assert_eq(contains(code, "Plain::with_defaults"), false)
}

///|
test "a literal is written the way its own type has to be" {
  let code = typed(
    (
      #|type Q {
      #|  n64:  int64   `form:"n64,default=1"`
      #|  un:   uint     `form:"un,default=2"`
      #|  un64: uint64   `form:"un64,default=3"`
      #|  f32:  float32  `form:"f32,default=4"`
      #|  ok:   bool     `form:"ok,default=true"`
      #|}
    ),
  )
  assert_eq(contains(code, "n64: if self.n64 == 0L { 1L }"), true)
  assert_eq(contains(code, "un: if self.un == 0U { 2U }"), true)
  assert_eq(contains(code, "un64: if self.un64 == 0UL { 3UL }"), true)
  assert_eq(
    contains(code, "f32: if self.f32 == (0.0 : Float) { (4.0 : Float) }"),
    true,
  )
  // an absent Bool decodes to false, so that is what a default replaces
  assert_eq(contains(code, "ok: if self.ok == false { true }"), true)
}

///|
test "a default= no literal of the field's type can spell is left out" {
  let code = typed("type Q {\n  ok: bool `form:\"ok,default=yes\"`\n}")
  assert_eq(contains(code, "with_defaults"), false)
  assert_eq(contains(code, "yes"), false)
}

///|
test "an open low end bounds nothing, and the message keeps its brackets" {
  let code = typed("type Q {\n  upto: int `form:\"upto,range=(:100)\"`\n}")
  assert_eq(contains(code, "if self.upto >= 100 {"), true)
  // the low end is open, so nothing is compared against it
  assert_eq(contains(code, "self.upto <"), false)
  assert_eq(
    contains(code, "return Some(\"upto is out of range (:100)\")"),
    true,
  )
}

///|
test "a constraint the field's type cannot compare against is left out" {
  // `options=` on a list has no literal to test, and a `range=` bounds numbers only
  let code = typed(
    (
      #|type Odd {
      #|  tags: []string `json:"tags,options=a|b"`
      #|  note: string   `json:"note,range=[1:3]"`
      #|}
    ),
  )
  assert_eq(contains(code, "self.tags !="), false)
  assert_eq(contains(code, "tags is not one of"), false)
  assert_eq(contains(code, "self.note <"), false)
  assert_eq(contains(code, "note is out of range"), false)
  // the required check on `note` is still there, so `check` is still generated
  assert_eq(contains(code, "return Some(\"note is required\")"), true)
}
