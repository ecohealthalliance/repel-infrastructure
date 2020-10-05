#!/usr/bin/python3

'''
This code updates the REPEL table from promed mongodb
'''

from datetime import datetime
import docker
import os
import psycopg2
import pymongo
from pymongo import MongoClient
import time

script_version = 0.1

def add_post_repel(cur, curr_post):
    promed_id = curr_post['promedId']
    promed_url = 'https://promedmail.org/promed-post/?id={}'.format(promed_id)
    subject_description = ''
    if 'subject' in curr_post.keys() and 'description' in curr_post['subject'].keys():
        subject_description = curr_post['subject']['description']
    subject_region = ''
    if 'subject' in curr_post.keys() and 'region' in curr_post['subject'].keys():
        subject_region = curr_post['subject']['region']
    subject_additional_info = ''
    if 'subject' in curr_post.keys() and 'additionalInfo' in curr_post['subject'].keys():
        subject_additional_info = curr_post['subject']['additionalInfo']
    subject_disease_labels = ''
    if 'subject' in curr_post.keys() and 'disease_labels' in curr_post['subject'].keys():
        subject_disease_labels = curr_post['subject']['disease_labels']
    if 'promedDate' in curr_post.keys():
        promed_year = curr_post['promedDate'].year
        if curr_post['promedDate'].month < 7:
            promed_semester = 1
        else:
            promed_semester = 2
    epitator_counts = ''
    if 'epitator_counts' in curr_post.keys():
        epitator_counts = curr_post['epitator_counts']
    epitator_keywords_disease = ''
    if 'epitator_keywords_disease' in curr_post.keys():
        epitator_keywords_disease = curr_post['epitator_keywords_disease']
    epitator_keywords_species = ''
    if 'epitator_keywords_species' in curr_post.keys():
        epitator_keywords_species = curr_post['epitator_keywords_species']
    epitator_geonames_countries = ''
    if 'epitator_geonames' in curr_post.keys():
        epitator_geonames_countries = curr_post['epitator_geonames']

    print('*** record start ***')
    print(promed_id)
    print(promed_url)
    print(subject_description)
    print(subject_region)
    print(subject_additional_info)
    print(subject_disease_labels)
    print(promed_year)
    print(promed_semester)
    print(epitator_counts)
    print(epitator_keywords_disease)
    print(epitator_keywords_species)
    print(epitator_geonames_countries)
    print()

    sql = '''INSERT INTO promed_posts(promed_id, promed_url, subject_description,
                                      subject_region, subject_additional_info,
                                      subject_disease_labels, promed_year,
                                      promed_semester, epitator_counts,
                                      epitator_keywords_disease,
                                      epitator_keywords_species,
                                      epitator_geonames)
                    VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)'''
    record_to_insert = (promed_id, promed_url, subject_description, subject_region,
                        subject_additional_info, subject_disease_labels,
                        promed_year, promed_semester, epitator_counts,
                        epitator_keywords_disease, epitator_keywords_species,
                        epitator_geonames_countries)
    print(record_to_insert)
    cur.execute(sql, record_to_insert)

def post_in_db(cur, post):
    # FIX: use change following query to technique above
    sql = "SELECT * FROM promed_posts WHERE promed_id = {}".format(post['promedId'])
    cur.execute(sql)
    if cur.rowcount == 0:
        return False
    else:
        return True

###########  end utility fucntions, start script content

### make postgres connection

dsn = "host={0} port={1} dbname={2} user={3} password={4}".format(os.environ['POSTGRES_HOST'],
                                                                  os.environ['POSTGRES_PORT'],
                                                                  os.environ['POSTGRES_DB'],
                                                                  os.environ['POSTGRES_USER'],
                                                                  os.environ['POSTGRES_PASSWORD'])
conn = psycopg2.connect(dsn)
cur = conn.cursor()

## create promed postgres table if it doesn't exist

sql = ''' SELECT * FROM information_schema.tables where table_name='promed_posts' '''
cur.execute(sql)
if cur.rowcount == 0:
    sql = ''' CREATE TABLE promed_posts (
                     promed_id INTEGER PRIMARY KEY,
                     promed_url VARCHAR(255),
                     subject_description VARCHAR(1023),
                     subject_region VARCHAR(255),
                     subject_additional_info VARCHAR(1023),
                     subject_disease_labels VARCHAR(1023),
                     promed_year INTEGER,
                     promed_semester INTEGER,
                     epitator_counts VARCHAR(1023),
                     epitator_keywords_disease VARCHAR(1023),
                     epitator_keywords_species VARCHAR(1023),
                     epitator_geonames VARCHAR(4095) ) '''
    cur.execute(sql)


### promed mongodb connection

client = MongoClient('mongo', 27017)
db = client.promed
posts = db.posts
all_posts = posts.find()
for post in all_posts:
    if not post_in_db(cur, post):
        add_post_repel(cur, post)

cur.close()
conn.commit()
