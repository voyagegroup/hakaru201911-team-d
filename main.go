package main

import (
	"log"
	"net/http"
	"strings"

	"database/sql"

	"os"

	_ "github.com/go-sql-driver/mysql"
)

type DBStruct struct {
	Name  string
	Value string
}

func initDB() *sql.DB {
	dataSourceName := os.Getenv("HAKARU_DATASOURCENAME")
	if dataSourceName == "" {
		dataSourceName = "root:password@tcp(127.0.0.1:13306)/hakaru"
	}

	db, err := sql.Open("mysql", dataSourceName)
	if err != nil {
		panic(err.Error())
	}
	return db
}

// BulkInsert is
func BulkInsert(resc []DBStruct, db *sql.DB) (err error) {
	rescInterface := []interface{}{}
	stmt := "INSERT INTO eventlog(at, name, value) values"

	for _, value := range resc {
		stmt += "(Now(),?,?),"
		rescInterface = append(rescInterface, value.Name)
		rescInterface = append(rescInterface, value.Value)
	}

	stmt = strings.TrimRight(stmt, ",")

	_, err = db.Exec(stmt, rescInterface...)
	return
}

func main() {

	db := initDB()

	defer db.Close()
	// connectionする数を制限する
	// RDS が 66 のConnectionができるので、５台のインスタンスを立てることを想定し、 66/5=15...1
	db.SetMaxOpenConns(6)

	var values []DBStruct
	// t := time.Now()

	hakaruHandler := func(w http.ResponseWriter, r *http.Request) {

		name := r.URL.Query().Get("name")
		value := r.URL.Query().Get("value")

		values = append(values, DBStruct{Name: name, Value: value})

		if len(values) > 10 {
			go BulkInsert(values, db)
			values = nil
		}

		origin := r.Header.Get("Origin")
		if origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
		} else {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		}
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET")
	}

	http.HandleFunc("/hakaru", hakaruHandler)
	http.HandleFunc("/ok", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(200) })

	// start server
	if err := http.ListenAndServe(":8081", nil); err != nil {
		log.Fatal(err)
	}
}
