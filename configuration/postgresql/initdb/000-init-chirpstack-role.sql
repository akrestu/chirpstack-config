CREATE ROLE chirpstack WITH LOGIN PASSWORD 'chirpstack';
   ALTER ROLE chirpstack CREATEDB;
   GRANT ALL PRIVILEGES ON DATABASE chirpstack TO chirpstack;