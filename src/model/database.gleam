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

    create table if not exists projects (
      id integer primary key autoincrement,
      owner_id integer not null,
      
      head text default \"<title>Hello world!</title>\",
      body text default \"<h1>Hello project!</h1>\",
      css text default \"body { font-family: sans-serif; }\",
      js text default \"\",
      modules text not null default \"{}\",
    
      foreign key(owner_id) references users(id)
    );
  "
    |> sqlight.exec(conn)

  conn
}
