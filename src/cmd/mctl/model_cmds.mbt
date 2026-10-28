// `mctl model …` — the model generators that work from a spec rather than from a
// live database: `mongo` (a document model over a collection port) and, further
// down, the cache-aware CRUD layer.

///|
/// `mctl model mongo <file>` — the document model of the spec, written beside it:
/// `<service>_mongo.mbt`, one `Doc` struct and one typed `Repo` per `type` block.
async fn model_mongo(input : String) -> Unit {
  try {
    let spec = read_spec(input)
    let out = dir_of(input) + @moonctl.mongo_file_name(spec.service)
    @fs.write_file(
      out,
      @moonctl.generate_mongo(spec),
      create_mode=CreateOrTruncate,
    )
    println("mctl: generated " + out + " from " + input)
  } catch {
    e => println("mctl: cannot model " + input + ": " + e.to_string())
  }
}

///|
/// `mctl model cache <file.api>` — the cache-aside CRUD layer for the spec's tables,
/// written beside it: `<service>_cache.mbt`. The record types it names are the ones
/// `mctl model` generates for the same spec, so the two files belong in one package.
async fn model_cache(input : String) -> Unit {
  try {
    let spec = read_spec(input)
    let out = dir_of(input) + @moonctl.cache_file_name(spec.service)
    @fs.write_file(
      out,
      @moonctl.generate_cached(spec),
      create_mode=CreateOrTruncate,
    )
    println("mctl: generated " + out + " from " + input)
  } catch {
    e => println("mctl: cannot cache " + input + ": " + e.to_string())
  }
}
