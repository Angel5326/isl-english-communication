import os
import glob

class VideoRetriever:
    """
    Given a gloss sequence, return paths to corresponding video clips.
    Assumes videos are named as <gloss>.mp4 in dataset/videos/
    """
    def __init__(self, video_root="dataset/raw/"):
        self.video_root = video_root
        # Build index: gloss -> video path
        self.index = {}
        for gloss_dir in glob.glob(os.path.join(video_root, "*")):
            gloss = os.path.basename(gloss_dir)
            # Find first .mp4 in that directory
            videos = glob.glob(os.path.join(gloss_dir, "*.mp4"))
            if videos:
                self.index[gloss.upper()] = videos[0]  # take first

    def get_video_paths(self, gloss_sequence):
        """
        Input: "GO SCHOOL TOMORROW"
        Returns: list of video paths
        """
        glosses = gloss_sequence.split()
        paths = []
        for g in glosses:
            g_upper = g.upper()
            if g_upper in self.index:
                paths.append(self.index[g_upper])
            else:
                # fallback: maybe we have a file name without extension?
                # We'll just ignore
                pass
        return paths

# Example
if __name__ == "__main__":
    retriever = VideoRetriever("dataset/raw/")
    paths = retriever.get_video_paths("GO SCHOOL TOMORROW")
    print(paths)