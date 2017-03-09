backend server_auth {
    .host = "auth";
    .port = "8080";
}

backend server_download {
    .host = "download";
    .port = "8080";
}

backend server_anon {
    .host = "anon";
    .port = "8080";
}

import std;
import directors;

sub vcl_init {

  new cluster_anon = directors.round_robin();
  new cluster_auth = directors.round_robin();
  new cluster_download = directors.round_robin();

  cluster_auth.add_backend(server_auth);
  cluster_download.add_backend(server_download);
  cluster_anon.add_backend(server_anon);

}
