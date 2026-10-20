std = "lua54"
-- .rocks/ is where `make setup` installs tools locally; CI installs them into
-- .lua/ and .luarocks/. None of it is our code.
exclude_files = { ".rocks/**", ".lua/**", ".luarocks/**" }

files["spec/**"] = { std = "+busted" }
