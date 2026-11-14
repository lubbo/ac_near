# Requirements

1. Real Penalty features
    - is providing a feature that counts how many times a driver cut the track
    - is providing settings to define how many track cuts the driver is allowed to do before a penalty is applied
    - is providing settings to define which penalty is assigned to drivers that exceeds maximum track cuts, in different kind of penalties, like pit drive through, stop and go.
    - is a python app, the source code is available in 'Real Penalty - App - v.1.05.01' directory

2. We need to add to the `near` app additional information for driver ahead and behind:
    - Max allowed track cuts
    - Current track cuts
    - Penalty already applied to driver

# Execution plan

1. Don't start conding, collect information about required python API to call to retrieve Real Penalty information: where Real Penalty is storing such information and how to retrieve it 
2. Document in a new file named TrackCutCount.analysis.md the result of your analysis

