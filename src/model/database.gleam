import sqlight

fn setup(conn: sqlight.Connection) {
  let assert Ok(Nil) =
    "
    create table if not exists users (
      id seqential primary key,
      provider text,
      name text,
      email text,
      
      access_token text,
      refresh_token text
    );
  "
    |> sqlight.exec(conn)
}
