#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <microhttpd.h>
#include <mysql/mysql.h>

// ==============================
// 状態フラグと共有バッファ
// ==============================

volatile int request_ready = 0;
volatile int response_ready = 0;

char request_zip[32] = "";
char request_addr[256] = "";
int request_zip_btn = 0;
int request_addr_btn = 0;

char *response_html = NULL;

// ==============================
// MySQL ラッパー関数
// ==============================

char* fetch_by_zip(const char* zip) {
    MYSQL *conn = mysql_init(NULL);
    if (!mysql_real_connect(conn, "localhost", "cocozip", "BB4-QerHVORyNIzr", "zipcode_db", 0, NULL, 0)) {
        return strdup("<div class='card'>DB接続失敗</div>");
    }

    char query[256];
    snprintf(query, sizeof(query),
             "SELECT zipcode, prefectures, city, town FROM zipcode WHERE zipcode LIKE '%s%%' LIMIT 50",
             zip);

    if (mysql_query(conn, query)) {
        mysql_close(conn);
        return strdup("<div class='card'>クエリ失敗</div>");
    }

    MYSQL_RES *res = mysql_store_result(conn);
    MYSQL_ROW row;
    size_t bufsize = 8192;
    char *result = malloc(bufsize);
    size_t len = 0;

    while ((row = mysql_fetch_row(res))) {
        char line[512];
        snprintf(line, sizeof(line),
                 "%s\t%s\t%s\t%s\n", row[0], row[1], row[2], row[3]);
        size_t l = strlen(line);
        if (len + l + 1 >= bufsize) {
            bufsize *= 2;
            result = realloc(result, bufsize);
        }
        strcpy(result + len, line);
        len += l;
    }

    mysql_free_result(res);
    mysql_close(conn);
    return result;
}

char* fetch_by_addr(const char* addr) {
    MYSQL *conn = mysql_init(NULL);
    if (!mysql_real_connect(conn, "localhost", "cocozip", "BB4-QerHVORyNIzr", "zipcode_db", 0, NULL, 0)) {
        return strdup("<div class='card'>DB接続失敗</div>");
    }

    char query[512];
    snprintf(query, sizeof(query),
             "SELECT zipcode, prefectures, city, town FROM zipcode WHERE CONCAT(prefectures,city,town) LIKE '%%%s%%' LIMIT 50",
             addr);

    if (mysql_query(conn, query)) {
        mysql_close(conn);
        return strdup("<div class='card'>クエリ失敗</div>");
    }

    MYSQL_RES *res = mysql_store_result(conn);
    MYSQL_ROW row;
    size_t bufsize = 8192;
    char *result = malloc(bufsize);
    size_t len = 0;

    while ((row = mysql_fetch_row(res))) {
        char line[512];
        snprintf(line, sizeof(line),
                 "%s\t%s\t%s\t%s\n", row[0], row[1], row[2], row[3]);
        size_t l = strlen(line);
        if (len + l + 1 >= bufsize) {
            bufsize *= 2;
            result = realloc(result, bufsize);
        }
        strcpy(result + len, line);
        len += l;
    }

    mysql_free_result(res);
    mysql_close(conn);
    return result;
}

// ==============================
// microhttpd ラッパー
// ==============================

#define PORT 8109
// main関数や answer_to_connection の前に追加！
static enum MHD_Result serve_file(struct MHD_Connection *connection, const char *filepath);


static enum MHD_Result answer_to_connection(void *cls, struct MHD_Connection *connection,
                                            const char *url, const char *method,
                                            const char *version, const char *upload_data,
                                            size_t *upload_data_size, void **con_cls) {
    const char *zip = MHD_lookup_connection_value(connection, MHD_GET_ARGUMENT_KIND, "zip");
    const char *addr = MHD_lookup_connection_value(connection, MHD_GET_ARGUMENT_KIND, "addr");
    const char *zip_btn = MHD_lookup_connection_value(connection, MHD_GET_ARGUMENT_KIND, "zip-btn");
    const char *addr_btn = MHD_lookup_connection_value(connection, MHD_GET_ARGUMENT_KIND, "addr-btn");

    if (strcmp(url, "/docs/readme.html") == 0) {
        return serve_file(connection, "./docs/readme.html");
    }
    if (strcmp(url, "/docs/readme.md") == 0) {
        return serve_file(connection, "./docs/readme.md");
    }


    snprintf(request_zip, sizeof(request_zip), "%s", zip ? zip : "");
    snprintf(request_addr, sizeof(request_addr), "%s", addr ? addr : "");
    request_zip_btn = zip_btn ? 1 : 0;
    request_addr_btn = addr_btn ? 1 : 0;

    request_ready = 1;

    while (!response_ready) {
        usleep(1000);
    }

    struct MHD_Response *response = MHD_create_response_from_buffer(strlen(response_html),
                                                                (void *)response_html,
                                                                MHD_RESPMEM_MUST_COPY);
    MHD_add_response_header(response, "Content-Type", "text/html; charset=utf-8"); // ← 追加！
    int ret = MHD_queue_response(connection, MHD_HTTP_OK, response);
    MHD_destroy_response(response);

    response_ready = 0;
    return ret;
}

static enum MHD_Result serve_file(struct MHD_Connection *connection, const char *filepath) {
    FILE *fp = fopen(filepath, "rb");
    if (!fp) return MHD_NO;

    fseek(fp, 0, SEEK_END);
    long fsize = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    char *data = malloc(fsize);
    fread(data, 1, fsize, fp);
    fclose(fp);

    struct MHD_Response *response = MHD_create_response_from_buffer(fsize, data, MHD_RESPMEM_MUST_FREE);
    MHD_add_response_header(response, "Content-Type", "text/html; charset=utf-8");
    int ret = MHD_queue_response(connection, MHD_HTTP_OK, response);
    MHD_destroy_response(response);
    return ret;
}


void start_http_server() {
    struct MHD_Daemon *daemon;
    daemon = MHD_start_daemon(MHD_USE_INTERNAL_POLLING_THREAD, PORT, NULL, NULL,
                              &answer_to_connection, NULL, MHD_OPTION_END);
    if (!daemon) {
        fprintf(stderr, "HTTPサーバの起動に失敗しました\n");
        return;
    }
    printf("HTTPサーバ起動中: http://127.0.0.1:%d/\n", PORT);
}

// ==============================
// Schemeから呼び出す getter/setter
// ==============================

int get_request_ready() { return request_ready; }
void clear_request_ready() { request_ready = 0; }

int get_request_zip_btn() { return request_zip_btn; }
int get_request_addr_btn() { return request_addr_btn; }

const char* get_request_zip() { return request_zip; }
const char* get_request_addr() { return request_addr; }

void set_response_html(const char* html) {
    if (response_html) free(response_html);
    response_html = strdup(html);
    response_ready = 1;
}

