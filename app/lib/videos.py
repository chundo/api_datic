import json
import subprocess
import sys
import os
import boto3

# Instala yt_dlp si no está disponible
try:
    import yt_dlp
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "yt-dlp"])
    user_site = subprocess.check_output(
        [sys.executable, "-m", "site", "--user-site"], text=True
    ).strip()
    sys.path.append(user_site)
    import yt_dlp


def extract_video_info(video_url):
    ydl_opts = {
        'format': 'best',
        'getcomments': True,
        'quiet': True,
        'no_warnings': True,
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(video_url, download=False)

            return {
                "URL": video_url,
                "Title": info.get("title"),
                "Width": info.get("width"),
                "Height": info.get("height"),
                "Language": info.get("language"),
                "Channel": info.get("channel"),
                "Likes": info.get("like_count"),
                "ID": info.get("id"),
                "Description": info.get("description"),
                "Uploader": info.get("uploader"),
                "Uploader_ID": info.get("uploader_id"),
                "Upload_Date": info.get("upload_date"),
                "Duration": info.get("duration"),
                "View_Count": info.get("view_count"),
                "Comment_Count": info.get("comment_count"),
                "Thumbnail": info.get("thumbnail"),
                "Categories": info.get("categories"),
                "Tags": info.get("tags"),
                "Is_Live": info.get("is_live"),
                "Comments": info.get("comments", [])[:10]
            }
    except Exception as e:
        return {"error": f"Failed to extract video info: {str(e)}"}


def download_video(video_url):
    """
    Download a YouTube video using yt-dlp.
    Args:
        video_url (str): URL of the YouTube video.
    Returns:
        dict: Dictionary with download status and filename or error.
    """

    ydl_opts = {
        'format': 'best',
        'quiet': True,
        'outtmpl': '%(title)s.%(ext)s',  # Save as title.ext (e.g. VideoTitle.mp4)
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(video_url, download=True)
            filename = ydl.prepare_filename(info)
            return {"status": "success", "file": filename}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def upload_to_spaces(file_path, bucket_name, destination_path=None):
    """
    Upload a file to DigitalOcean Spaces and return the public URL.
    Args:
        file_path (str): Path to the local file to upload.
        bucket_name (str): Name of the Spaces bucket.
        destination_path (str, optional): Destination path in the bucket. Defaults to file's basename.
    Returns:
        dict: Dictionary with upload status and public URL or error message.
    """

    session = boto3.session.Session()
    client = session.client('s3',
                            region_name='nyc3',
                            endpoint_url='https://nyc3.digitaloceanspaces.com',
                            aws_access_key_id=os.getenv('DIGITAL_ACCESS_KEY'),
                            aws_secret_access_key=os.getenv('DIGITAL_SECRET_ACCESS'))
    try:
        # Determine the destination path if not provided
        if destination_path is None:
            destination_path = os.path.basename(file_path)

        video = f"videos/{destination_path}"

        # Upload the file to Spaces
        client.upload_file(
            Filename=file_path,
            Bucket=bucket_name,
            Key=video,
            ExtraArgs={
                'ACL': 'public-read'
            }
        )

        # Construct the public URL
        public_url = f"https://{bucket_name}.nyc3.digitaloceanspaces.com/{video}"

        return {
            "status": "success",
            "file_path": file_path,
            "destination_path": destination_path,
            "public_url": public_url
        }
    except Exception as e:
        return {"status": "error", "message": f"Failed to upload file: {str(e)}"}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Please provide a YouTube video URL as an argument."}))
        sys.exit(1)

    video_url = sys.argv[1].strip()

    if not video_url.startswith(("https://www.youtube.com", "https://youtu.be")):
        print(json.dumps({"error": "Invalid YouTube video URL."}))
        sys.exit(1)

    # Soporte para descarga si se incluye "--download"
    download_flag = "--download" in sys.argv
    upload_flag = "--upload" in sys.argv

    if download_flag:
        result = download_video(video_url)
        if result["status"] == "success" and upload_flag:
            # Upload the downloaded file to Spaces
            bucket_name = "ideardev"  # Replace with your actual bucket name
            upload_result = upload_to_spaces(result["file"], bucket_name)
            result["upload"] = upload_result
            # Eliminar el archivo local si la subida fue exitosa
            if upload_result["status"] == "success":
                try:
                    os.remove(result["file"])
                    result["local_file_deleted"] = True
                except Exception as e:
                    result["local_file_deleted"] = False
                    result["delete_error"] = f"Failed to delete local file: {str(e)}"
    else:
        result = extract_video_info(video_url)

    print(json.dumps(result, indent=4, ensure_ascii=False))