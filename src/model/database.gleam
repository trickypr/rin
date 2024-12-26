import sqlight

pub fn get(c) {
  sqlight.with_connection("app.db", c)
}

pub fn setup() {
  use conn <- get()

  let assert Ok(Nil) =
    "
    create table if not exists users (
      id integer primary key autoincrement,
      provider text,
      name text unique,
      
      access_token text
    );
  "
    |> sqlight.exec(conn)

  conn
}
